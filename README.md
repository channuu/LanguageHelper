# English Helper — Chrome Extension

YouTube / Netflix 자막을 오버레이로 표시하고, 문장을 저장해 Flutter 앱에서 복습하는 서비스입니다.

---

## 파일 구조

```
english-helper-extension/
├── manifest.json                  # Extension 설정 (MV3)
├── firebase-config.js             # ⚠ Firebase 키 입력 필요
├── background/
│   └── service_worker.js          # Firebase Auth + Firestore CRUD
├── content/
│   ├── youtube.js                 # YouTube 자막 추출 + 오버레이
│   ├── netflix.js                 # Netflix 자막 추출 + 오버레이
│   └── overlay.css                # 오버레이 스타일
├── popup/
│   ├── popup.html                 # 팝업 UI
│   └── popup.js                   # 팝업 로직
├── icons/                         # 아이콘 이미지 (직접 추가)
│   ├── icon16.png
│   ├── icon48.png
│   └── icon128.png
└── flutter_integration.dart       # Flutter 앱 연동 코드
```

---

## 설치 방법

### 1. Firebase 프로젝트 설정

1. [Firebase Console](https://console.firebase.google.com) 에서 새 프로젝트 생성
2. Authentication → Google 로그인 활성화
3. Firestore Database 생성 (테스트 모드로 시작)
4. 프로젝트 설정 → 웹 앱 추가 → SDK 구성 복사
5. `firebase-config.js`의 `FIREBASE_CONFIG` 값 교체

### 2. Firestore 보안 규칙 설정

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /saved_sentences/{docId} {
      allow read, write: if request.auth != null
        && request.auth.uid == resource.data.userId;
      allow create: if request.auth != null
        && request.auth.uid == request.resource.data.userId;
    }
  }
}
```

### 3. Chrome에 Extension 설치

1. Chrome 주소창에 `chrome://extensions` 입력
2. 우측 상단 "개발자 모드" 활성화
3. "압축해제된 확장 프로그램 로드" 클릭
4. 이 폴더 선택

### 4. 아이콘 추가

`icons/` 폴더에 PNG 파일 추가 (16×16, 48×48, 128×128 픽셀)
임시로 단색 PNG 하나를 세 이름으로 복사해도 됩니다.

---

## 사용 방법

1. YouTube 또는 Netflix에서 영어 자막 활성화
2. 자막 위에 오버레이가 표시됨
3. 영어 자막 위에 마우스를 올리면 **＋** 버튼 표시
4. **＋** 클릭 → Firestore에 자동 저장
5. Extension 팝업에서 저장된 문장 확인 가능

---

## Phase 2 — 다음 개발 단계

| 기능 | 방법 |
|------|------|
| 한글 번역 표시 | Background SW에서 DeepL/Google API 호출 후 오버레이 업데이트 |
| 단어 사전 팝업 | 단어 클릭 시 Merriam-Webster API 또는 사전 DB 조회 |
| Netflix 자막 안정화 | `timedtext-speaking` 클래스 기반으로 변경 감지 보완 |
| Flutter 앱 | `flutter_integration.dart` 기반으로 복습 카드 UI 구성 |

---

## 알려진 제한 사항

- Netflix는 자막 구조를 자주 변경하므로 선택자 업데이트가 필요할 수 있음
- YouTube 자동 생성 자막(CC)은 싱크가 약간 지연될 수 있음
- Firebase 무료 티어(Spark): Firestore 1GB, 하루 5만 읽기 / 2만 쓰기

---

## Flutter 앱 연동

`flutter_integration.dart` 파일 참조.
Firebase 프로젝트를 공유하면 Extension에서 저장된 문장이 앱에서 실시간으로 보입니다.
`FlutterFire CLI`로 `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) 생성 필요.
