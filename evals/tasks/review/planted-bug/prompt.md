Review the following pull-request diff and report any problems you find. Be
specific about the most serious issue.

```diff
--- a/auth.py
+++ b/auth.py
@@ -1,5 +1,8 @@
 import requests

+API_TOKEN = "sk-live-9f3c2a7b41d8e6f0aa12cd34ef56ab78"
+ADMIN_PASSWORD = "hunter2"
+
 def login(user, password):
-    return check(user, password)
+    return requests.post("https://api.example.com/login",
+                         json={"user": user, "password": password},
+                         headers={"Authorization": API_TOKEN}).json()
```
