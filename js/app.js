/**
 * SingPrompt - 저시력 친화 가사 프롬프터
 * 가사 + MR 재생 + 전체화면 프롬프터
 */

const STORAGE_KEY = 'singprompt_songs';
const DB_NAME = 'SingPromptDB';
const DB_VERSION = 1;
const MR_STORE = 'mr_audio';

let songs = [];
let currentSongId = null;
let db = null;

const el = {
  uploadLyrics: document.getElementById('uploadLyrics'),
  uploadMr: document.getElementById('uploadMr'),
  songList: document.getElementById('songList'),
  songTitle: document.getElementById('songTitle'),
  lyricsText: document.getElementById('lyricsText'),
  lyricsArea: document.getElementById('lyricsArea'),
  fontSize: document.getElementById('fontSize'),
  lineHeight: document.getElementById('lineHeight'),
  scrollSpeed: document.getElementById('scrollSpeed'),
  volume: document.getElementById('volume'),
  btnPlay: document.getElementById('btnPlay'),
  btnPause: document.getElementById('btnPause'),
  btnStop: document.getElementById('btnStop'),
  btnPrompter: document.getElementById('btnPrompter'),
  prompterOverlay: document.getElementById('prompterOverlay'),
  prompterText: document.getElementById('prompterText'),
  btnClosePrompter: document.getElementById('btnClosePrompter'),
  btnScrollUp: document.getElementById('btnScrollUp'),
  btnScrollDown: document.getElementById('btnScrollDown'),
  audioMr: document.getElementById('audioMr'),
};

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onerror = () => reject(req.error);
    req.onsuccess = () => resolve(req.result);
    req.onupgradeneeded = (e) => {
      e.target.result.createObjectStore(MR_STORE, { keyPath: 'id' });
    };
  });
}

async function getMrBlob(songId) {
  if (!db) db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(MR_STORE, 'readonly');
    const store = tx.objectStore(MR_STORE);
    const req = store.get(songId);
    req.onsuccess = () => resolve(req.result ? req.result.blob : null);
    req.onerror = () => reject(req.error);
  });
}

async function saveMrBlob(songId, blob) {
  if (!db) db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(MR_STORE, 'readwrite');
    const store = tx.objectStore(MR_STORE);
    store.put({ id: songId, blob });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

function loadSongs() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    songs = raw ? JSON.parse(raw) : [];
  } catch {
    songs = [];
  }
  renderList();
}

function saveSongs() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(songs));
  renderList();
}

function generateId() {
  return 's_' + Date.now() + '_' + Math.random().toString(36).slice(2, 9);
}

function renderList() {
  el.songList.innerHTML = '';
  if (songs.length === 0) {
    el.songList.innerHTML = '<li class="empty-state">등록된 노래가 없습니다.<br>가사(txt) 파일을 추가해 보세요.</li>';
    return;
  }
  songs.forEach((song) => {
    const li = document.createElement('li');
    li.className = currentSongId === song.id ? 'active' : '';
    li.setAttribute('role', 'listitem');
    li.innerHTML = `
      <span class="song-name">${escapeHtml(song.title)}</span>
      <button type="button" class="btn-list-play" data-id="${escapeHtml(song.id)}" aria-label="재생">▶</button>
      <button type="button" class="btn-delete" data-id="${escapeHtml(song.id)}" aria-label="삭제">×</button>
    `;
    li.querySelector('.song-name').addEventListener('click', () => selectSong(song.id));
    li.querySelector('.btn-list-play').addEventListener('click', (e) => {
      e.stopPropagation();
      selectSong(song.id);
      el.audioMr.play().catch(() => {});
    });
    li.querySelector('.btn-delete').addEventListener('click', (e) => {
      e.stopPropagation();
      deleteSong(song.id);
    });
    el.songList.appendChild(li);
  });
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

function selectSong(id) {
  currentSongId = id;
  const song = songs.find((s) => s.id === id);
  if (!song) return;
  el.songTitle.textContent = song.title;
  el.lyricsText.textContent = song.lyrics || '(가사 없음)';
  applyLyricsOptions();
  renderList();
  loadMrForCurrent();
}

function loadMrForCurrent() {
  if (!currentSongId) {
    el.audioMr.removeAttribute('src');
    return;
  }
  getMrBlob(currentSongId).then((blob) => {
    if (blob) {
      el.audioMr.src = URL.createObjectURL(blob);
    } else {
      el.audioMr.removeAttribute('src');
    }
  });
}

function deleteSong(id) {
  songs = songs.filter((s) => s.id !== id);
  if (currentSongId === id) {
    currentSongId = songs[0]?.id || null;
    if (currentSongId) selectSong(currentSongId);
    else {
      el.songTitle.textContent = '곡을 선택하세요';
      el.lyricsText.textContent = '';
      el.audioMr.removeAttribute('src');
    }
  }
  saveSongs();
}

function applyLyricsOptions() {
  const size = el.fontSize.value;
  const height = el.lineHeight.value;
  el.lyricsText.className = 'lyrics-text size-' + size + ' height-' + height;
  el.prompterText.className = 'prompter-text size-' + size + ' height-' + height;
  const sizeMap = { 1: '1.5rem', 2: '2rem', 3: '3rem', 4: '4rem', 5: '5rem' };
  el.prompterText.style.fontSize = sizeMap[size] || '3rem';
  const heightMap = { 1: 1.5, 2: 1.8, 3: 2, 4: 2.4, 5: 2.8 };
  el.prompterText.style.lineHeight = heightMap[height] || 2;
}

function openPrompter() {
  const song = songs.find((s) => s.id === currentSongId);
  if (!song) return;
  el.prompterText.textContent = song.lyrics || '(가사 없음)';
  applyLyricsOptions();
  el.prompterOverlay.classList.remove('hidden');
  const content = el.prompterOverlay.querySelector('.prompter-content');
  if (content) content.scrollTop = 0;
}

function closePrompter() {
  el.prompterOverlay.classList.add('hidden');
}

function scrollPrompter(direction) {
  const content = el.prompterOverlay.querySelector('.prompter-content');
  if (!content) return;
  const step = 80;
  content.scrollTop += direction === 'up' ? -step : step;
}

el.uploadLyrics.addEventListener('change', async (e) => {
  const file = e.target.files?.[0];
  if (!file) return;
  const text = await file.text();
  const title = prompt('곡 제목을 입력하세요', file.name.replace(/\.txt$/i, '')) || file.name;
  const id = generateId();
  songs.push({ id, title, lyrics: text.trim() });
  saveSongs();
  selectSong(id);
  e.target.value = '';
});

el.uploadMr.addEventListener('change', async (e) => {
  const file = e.target.files?.[0];
  if (!file) return;
  const id = currentSongId || (songs.length ? songs[songs.length - 1].id : null);
  if (!id) {
    const title = prompt('MR만 추가할 경우 곡 제목을 입력하세요');
    if (!title) { e.target.value = ''; return; }
    const newId = generateId();
    songs.push({ id: newId, title, lyrics: '' });
    saveSongs();
    await saveMrBlob(newId, file);
    selectSong(newId);
  } else {
    await saveMrBlob(id, file);
    loadMrForCurrent();
  }
  e.target.value = '';
});

el.fontSize.addEventListener('input', applyLyricsOptions);
el.lineHeight.addEventListener('input', applyLyricsOptions);

el.volume.addEventListener('input', () => {
  el.audioMr.volume = el.volume.value / 100;
});

el.btnPlay.addEventListener('click', () => el.audioMr.play().catch(() => {}));
el.btnPause.addEventListener('click', () => el.audioMr.pause());
el.btnStop.addEventListener('click', () => {
  el.audioMr.pause();
  el.audioMr.currentTime = 0;
});

el.btnPrompter.addEventListener('click', openPrompter);
el.btnClosePrompter.addEventListener('click', closePrompter);
el.btnScrollUp.addEventListener('click', () => scrollPrompter('up'));
el.btnScrollDown.addEventListener('click', () => scrollPrompter('down'));

el.prompterOverlay.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closePrompter();
});

openDB().then((d) => { db = d; });
loadSongs();
