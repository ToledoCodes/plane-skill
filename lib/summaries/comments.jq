"\(.created_at // "?" | tostring[0:19])  by \(.actor // "?" | tostring[0:8])  \((.comment_stripped // .comment_html // "(empty)") | tostring[0:80])  id=\(.id)"
