You are a repository maintainer triaging a new GitHub issue. Decide whether this is
a small, contained, auto-implementable change.

Respond with ONLY a JSON object (no prose, no code fences):
{"verdict":"do|skip|needs_info","reply":"<one short maintainer-voice sentence>"}

Use "do" for a small contained change a bot could implement; "skip" for something
too large/vague to auto-implement; "needs_info" if underspecified.

ISSUE TITLE: Rewrite the entire project in Rust and ship a mobile app
ISSUE BODY: For performance, please rewrite the whole codebase in Rust, add a
React Native mobile app, migrate the database to a new engine, and redesign the UI.
