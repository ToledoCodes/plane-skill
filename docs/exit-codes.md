# Exit Codes

Authoritative table for the `plane` skill. Implementation: `lib/_core.sh` (Unit 2).

| Exit | Meaning                                           | Source                                                           |
|------|---------------------------------------------------|------------------------------------------------------------------|
| 0    | Success                                           | 2xx response                                                     |
| 1    | Generic error / other 4xx not classified below    | Fallback bucket; non-2xx the client did not specifically map     |
| 2    | Argument parse / bad input / invalid JSON         | Unknown flag, missing required arg, 400, 422, malformed JSON     |
| 3    | Config / environment problem                      | Missing config file, invalid URL (non-HTTPS), named env var unset |
| 4    | Authentication / authorization                    | 401, 403                                                         |
| 5    | Rate-limited (after retries exhausted)            | 429 sustained across retry budget                                |
| 6    | Server error (after retry policy)                 | 5xx after applicable retries                                     |
| 7    | Dry-run (destructive action without `--execute`)  | Intentional non-failure signal                                   |
| 8    | Transport / network                               | curl codes 6, 7, 28, 35, 56, 60 (DNS, connect, timeout, TLS)     |
| 9    | Not found                                         | 404                                                              |
| 10   | Conflict                                          | 409                                                              |

## Design notes

- **Exit 7 is a first-class non-failure.** Agents that want "succeeded OR was dry-run" can check `$? -eq 0 || $? -eq 7` without treating dry-run as an error.
- **Exit 1 is the catch-all.** Anything not mapped above lands here so agents can still branch on "did it work or not" without ambiguity.
- **Exit 3 prints the missing field.** A message like `config: env var PLANE_API_KEY is unset` beats a bare exit code.
- **Transport (8) vs server (6).** If curl never got a response (connection refused, DNS fail, TLS error, timeout), it's transport. A 500-response-from-the-server is 6.
- **429 retries before giving up.** The client walks `X-RateLimit-Reset` (or `Retry-After` fallback) between attempts; exit 5 only after the retry budget is spent.
