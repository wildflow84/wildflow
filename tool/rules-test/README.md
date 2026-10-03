# Firestore 보안 규칙 테스트

에뮬레이터로 `firestore.rules`를 검사한다 (24건). 로컬에서만 쓰고 CI에는 넣지 않았다.

```
cd tool/rules-test && npm install
npx firebase emulators:exec --only firestore --project demo-ourday "node rules.test.js"
```
