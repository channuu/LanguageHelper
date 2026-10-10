# English Helper

YouTube · Netflix · Disney+ · 쿠팡플레이에서 영어 자막과 번역을 함께 보여주고,
마음에 든 문장과 단어를 저장해 모바일 앱에서 복습하는 서비스입니다.

Chrome 확장 프로그램(`/`)과 Flutter 앱(`mobile/`) 두 표면으로 이루어져 있고,
저장한 항목은 같은 계정으로 로그인하면 Firebase를 통해 양쪽을 오갑니다.

---

## 확장 프로그램

### 구조

```
manifest.json            MV3 설정
background/              서비스워커 — 인증, 동기화, 사전 조회, 내보내기
core/                    플랫폼과 무관한 UI와 로직
  adapter-interface.js     어댑터 계약 + 전체 기능 on/off
  subtitle-engine.js       영상 위 자막 오버레이
  script-panel.js          우측 스크립트 패널
  settings-panel.js        자막 설정
  library-panel.js         저장 목록
  word-popup.js            단어 팝업
  cue-utils.js             청크 분할 — 오버레이와 패널이 공유
  storage.js
adapters/                플랫폼별 자막 수집 (youtube, netflix, disney, coupang)
inject/                  MAIN world 스크립트 — 네트워크 가로채기
popup/                   툴바 아이콘 팝업
auth/ export/            실행 중에 열리는 확장 페이지
cloud/                   Firebase 인증 · Firestore 동기화
lexicon/                 사전 조회와 캐시
ui/                      디자인 토큰, 오버레이 스타일, 폰트
tools/                   빌드 스크립트 (저장소 전용, 패키지에 포함되지 않음)
```

### 새 플랫폼 추가하기

`core/adapter-interface.js`의 `SubtitleAdapter`를 상속한 파일 하나를
`adapters/`에 두고 manifest에 등록하면 됩니다. 코어는 건드리지 않습니다.

플랫폼마다 자막을 꺼내는 방법이 다릅니다. 네 어댑터 모두 DOM을 긁는 대신
**플레이어가 받아오는 자막 파일을 가로채는 방식**을 씁니다 — DOM 자막은
shadow DOM에 있거나(Disney+) 구조가 자주 바뀌어 신뢰할 수 없습니다.

### 개발

```bash
npm test                 # 순수 모듈 테스트 (lexicon, cloud)
npm run build:dict       # dumps/ → dist/dict 사전 빌드
npm run package          # 웹 스토어 제출용 ZIP → build/
```

확장을 설치하려면 `chrome://extensions`에서 개발자 모드를 켜고 이 폴더를
"압축해제된 확장 프로그램 로드"로 선택합니다.

> **확장 코드를 고친 뒤에는 확장을 새로고침하고, 이미 열려 있던 탭도
> 새로고침해야 합니다.** 확장만 리로드하면 기존 탭에는 예전 content script가
> 그대로 남아 변경이 반영되지 않습니다.

브라우저 측 코드(`core/`, `adapters/`, `inject/`)는 `npm test`가 커버하지
않습니다 — 실제 재생 페이지에서 확인해야 합니다.

## 모바일 앱

Flutter. 저장 목록, 플래시카드, 학습 타이머와 주간 목표, 설정 화면으로
이루어져 있습니다.

```bash
cd mobile
flutter test
flutter run
```

## 스토어 등록

개인정보처리방침은 `dist/privacy.html`(한국어)과 `dist/privacy-en.html`에
있고, Firebase Hosting으로 배포하면 `/privacy.html`로 열립니다.
운영자명과 문의 이메일이 플레이스홀더로 남아 있습니다.

## 설정

`cloud/config.js`에 Firebase 프로젝트 식별자가 있습니다. 웹 API 키는 비밀이
아니며, 접근 통제는 `firestore.rules`가 담당합니다 — 각 사용자는 자신의
`users/{uid}` 문서에만 접근할 수 있습니다.
