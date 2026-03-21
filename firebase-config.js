// ================================================================
// firebase-config.js  — 이 파일의 값을 본인 Firebase 프로젝트로 교체하세요
// Firebase Console > 프로젝트 설정 > 웹 앱 추가 > SDK 구성에서 복사
// ================================================================

export const FIREBASE_CONFIG = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID"
};

// Firestore 컬렉션 이름
export const COLLECTIONS = {
  USERS: "users",
  SAVED_SENTENCES: "saved_sentences",
  REVIEW_SESSIONS: "review_sessions"
};
