// cloud/config.js
// Firebase Web API 키는 비밀이 아니다. 클라이언트에 노출되는 것을 전제로
// 설계된 식별자이며, 실제 접근 통제는 firestore.rules가 담당한다.
export const FIREBASE = {
  apiKey: 'AIzaSyCpR6j0wcFMAR8OA5QPzwu-2rtnJvj-qB4',
  projectId: 'language-helper-d1de6'
};

export const IDENTITY_BASE = 'https://identitytoolkit.googleapis.com/v1';
export const TOKEN_BASE = 'https://securetoken.googleapis.com/v1';
export const FIRESTORE_BASE =
  `https://firestore.googleapis.com/v1/projects/${FIREBASE.projectId}/databases/(default)/documents`;
