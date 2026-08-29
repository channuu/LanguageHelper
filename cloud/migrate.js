// cloud/migrate.js
// 확장의 저장 항목을 Firestore와 같은 snake_case 스키마로 옮긴다.
// 멱등이다 — 서비스워커가 몇 번 재시작해도 안전하게 다시 돌릴 수 있다.

export const SCHEMA_VERSION = 1;

function pick(item, snake, camel, fallback) {
  if (item[snake] !== undefined) return item[snake];
  if (item[camel] !== undefined) return item[camel];
  return fallback;
}

function common(item) {
  const savedAt = pick(item, 'saved_at', 'savedAt', null)
    || new Date().toISOString();
  return {
    id: item.id,
    platform: item.platform || '',
    content_title: pick(item, 'content_title', 'contentTitle', ''),
    content_id: pick(item, 'content_id', 'contentId', ''),
    timestamp: item.timestamp || 0,
    saved_at: savedAt,
    review_count: pick(item, 'review_count', 'reviewCount', 0),
    next_review_at: pick(item, 'next_review_at', 'nextReviewAt', null),
    review_level: pick(item, 'review_level', 'reviewLevel', 0),
    last_reviewed_at: pick(item, 'last_reviewed_at', 'lastReviewedAt', null),
    updated_at: pick(item, 'updated_at', 'updatedAt', null) || savedAt,
    synced_at: item.synced_at !== undefined ? item.synced_at : null
  };
}

export function migrateWord(item) {
  return {
    ...common(item),
    word: item.word || '',
    definition: item.definition || '',
    sentence: item.sentence || '',
    translation: item.translation || ''
  };
}

export function migrateSentence(item) {
  return {
    ...common(item),
    original: item.original || '',
    translation: item.translation || ''
  };
}
