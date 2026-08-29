(function () {
  'use strict';

  function generateId() {
    return crypto.randomUUID
      ? crypto.randomUUID()
      : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
          const r = Math.random() * 16 | 0;
          return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
        });
  }

  const Storage = {
    async saveWord({ word, definition, sentence, translation, timestamp }) {
      const meta = window.EH.adapter?.getPlatformMeta() || { platform: 'unknown', title: '', contentId: '' };
      const now = new Date().toISOString();
      const item = {
        id: generateId(),
        word, definition: definition || '', sentence: sentence || '',
        translation: translation || '',
        platform: meta.platform,
        content_title: meta.title,
        content_id: meta.contentId,
        timestamp: timestamp || 0,
        saved_at: now,
        review_count: 0, next_review_at: null,
        review_level: 0, last_reviewed_at: null,
        updated_at: now, synced_at: null
      };
      return chrome.runtime.sendMessage({ type: 'SAVE_WORD', payload: item });
    },

    async saveSentence({ original, translation, timestamp }) {
      const meta = window.EH.adapter?.getPlatformMeta() || { platform: 'unknown', title: '', contentId: '' };
      const now = new Date().toISOString();
      const item = {
        id: generateId(),
        original, translation: translation || '',
        platform: meta.platform,
        content_title: meta.title,
        content_id: meta.contentId,
        timestamp: timestamp || 0,
        saved_at: now,
        review_count: 0, next_review_at: null,
        review_level: 0, last_reviewed_at: null,
        updated_at: now, synced_at: null
      };
      return chrome.runtime.sendMessage({ type: 'SAVE_SENTENCE', payload: item });
    },

    async getAll() {
      return chrome.runtime.sendMessage({ type: 'GET_ALL' });
    },

    async deleteItem(type, id) {
      return chrome.runtime.sendMessage({ type: 'DELETE_ITEM', payload: { type, id } });
    }
  };

  window.EH = window.EH || {};
  window.EH.Storage = Storage;
})();
