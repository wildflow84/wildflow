// 웹 푸시(백그라운드) 수신용 서비스 워커. 앱이 닫혀 있거나 다른 탭일 때 알림을 띄운다.
// Firebase 웹 설정은 공개 값이다 (config/firebase_public.json 과 같은 값).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC8XnK7iMapc-UHnYCnhIY11NwuI29qvVA',
  authDomain: 'soondaehui.firebaseapp.com',
  projectId: 'soondaehui',
  storageBucket: 'soondaehui.firebasestorage.app',
  messagingSenderId: '915456483126',
  appId: '1:915456483126:web:44a6bdbf44ebc047889d97',
});

// 서버가 notification 페이로드로 보내므로 브라우저가 자동으로 알림을 띄운다.
firebase.messaging();
