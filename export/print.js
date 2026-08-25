// 확장 페이지(chrome-extension:// 오리진)에서 실행된다 — 호스트 사이트의 CSP를
// 받지 않으므로 Netflix/Disney+에서도 동작한다. 이 페이지의 존재 이유 자체가
// 그것이다.
(function () {
  'use strict';

  const root = document.getElementById('eh-print-root');

  function showError(msg) {
    const div = document.createElement('div');
    div.className = 'eh-print-error';
    div.textContent = msg;
    root.appendChild(div);
  }

  async function main() {
    const id = new URLSearchParams(location.search).get('id');
    if (!id) {
      showError('내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요.');
      return;
    }

    const key = 'eh_print_' + id;
    let html;
    try {
      const stored = await chrome.storage.session.get(key);
      html = stored[key];
    } catch (err) {
      console.error('[EH Print] session read failed', err);
      showError('내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요.');
      return;
    }

    // 한 번 쓰고 버리는 값이다 — 읽자마자 지워서 세션 저장소에 스크립트가
    // 쌓이지 않게 한다. 이 탭을 새로고침하면 아래 not-found 분기로 간다.
    chrome.storage.session.remove(key);

    if (!html) {
      showError('내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요.');
      return;
    }

    // 문서 전체를 innerHTML로 통째로 넣지 않는다 — DOMParser로 파싱해
    // <style>과 body 자식만 옮긴다. 자막 원문은 이미 이스케이프되지만,
    // 방어적으로 한 겹 더 둔다. (MV3 확장 페이지의 기본 CSP script-src 'self'가
    // 인라인 스크립트/이벤트 핸들러 실행을 막는 것이 그 다음 겹이다.)
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.head.querySelectorAll('style').forEach(s => document.head.appendChild(s));
    while (doc.body.firstChild) root.appendChild(doc.body.firstChild);

    const title = doc.querySelector('title')?.textContent;
    if (title) document.title = title;

    // 폰트가 로드되기 전에 인쇄하면 줄바꿈 위치가 화면과 달라져 조판이 틀어진다.
    await document.fonts.ready;
    window.print();
  }

  main();
})();
