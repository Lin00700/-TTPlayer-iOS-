import Foundation

/// Wi-Fi 传歌的网页（由 NWListener 直接吐出，不需要任何外部资源）。
enum UploadPage {
    static let html: String = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#14120f">
<title>千千静听 · Wi-Fi 传歌</title>
<style>
  :root {
    --paper: #1b1813;
    --paper-2: #221e17;
    --line: #4a3f2c;
    --ink: #ede4d0;
    --ink-dim: #a79b84;
    --seal: #a8362f;
    --gold: #c9a86a;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    min-height: 100vh;
    background:
      radial-gradient(1200px 600px at 20% -10%, rgba(201,168,106,.16), transparent 60%),
      radial-gradient(900px 500px at 110% 10%, rgba(168,54,47,.16), transparent 55%),
      linear-gradient(160deg, #1f1b14, #0a0806 70%);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .shell { max-width: 760px; margin: 0 auto; padding: 28px 20px 60px; }
  header { display: flex; align-items: center; gap: 16px; margin-bottom: 26px; }
  .logo {
    width: 54px; height: 54px; border-radius: 15px; flex: none;
    display: grid; place-items: center;
    font-size: 28px; color: var(--gold);
    background: linear-gradient(160deg, #322b20, #14110c);
    border: 1px solid var(--line);
    box-shadow: inset 0 1px 0 rgba(255,255,255,.10), 0 8px 24px rgba(0,0,0,.45);
  }
  h1 { font-size: 20px; margin: 0 0 4px; letter-spacing: .5px; font-weight: 600; }
  h1 span { font-size: 12px; color: var(--gold); margin-left: 8px; letter-spacing: 2px; font-weight: 500; }
  .sub { margin: 0; font-size: 12.5px; color: var(--ink-dim); }
  .drop {
    display: block; cursor: pointer; border-radius: 18px; padding: 30px 22px; text-align: center;
    background: linear-gradient(170deg, rgba(255,255,255,.045), rgba(255,255,255,.01));
    border: 1.5px dashed rgba(201,168,106,.42);
    transition: border-color .18s, background .18s, transform .18s;
  }
  .drop.hot { border-color: var(--gold); background: rgba(201,168,106,.10); transform: translateY(-2px); }
  .drop input { display: none; }
  .drop-icon { font-size: 30px; color: var(--gold); margin-bottom: 10px; }
  .drop strong { display: block; font-size: 15px; margin-bottom: 6px; }
  .drop span { font-size: 12.5px; color: var(--ink-dim); line-height: 1.7; }
  .queue { list-style: none; margin: 18px 0 0; padding: 0; display: grid; gap: 8px; }
  .queue li {
    background: rgba(255,255,255,.04); border: 1px solid rgba(201,168,106,.16);
    border-radius: 12px; padding: 10px 12px; font-size: 13px;
  }
  .queue .name { display: flex; justify-content: space-between; gap: 10px; margin-bottom: 8px; }
  .queue .name b { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .queue .name i { font-style: normal; color: var(--ink-dim); font-size: 12px; flex: none; }
  .bar { height: 4px; border-radius: 999px; background: rgba(255,255,255,.09); overflow: hidden; }
  .bar > div { height: 100%; width: 0%; border-radius: 999px; background: linear-gradient(90deg, var(--gold), var(--seal)); transition: width .12s linear; }
  .ok { color: #9fd3a6; }
  .bad { color: #e28479; }
  .files { margin-top: 30px; }
  .files-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
  .files-head h2 { font-size: 14px; margin: 0; font-weight: 600; letter-spacing: .5px; }
  button {
    font: inherit; font-size: 12.5px; color: var(--ink); cursor: pointer;
    background: rgba(255,255,255,.06); border: 1px solid var(--line);
    border-radius: 999px; padding: 6px 14px;
  }
  button:hover { border-color: var(--gold); color: var(--gold); }
  #list { list-style: none; margin: 0; padding: 0; border-top: 1px solid rgba(201,168,106,.14); }
  #list li {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 2px; font-size: 13px;
    border-bottom: 1px solid rgba(201,168,106,.10);
  }
  #list .idx { width: 22px; color: var(--ink-dim); font-size: 11px; text-align: right; flex: none; }
  #list .title { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #list .size { color: var(--ink-dim); font-size: 11.5px; flex: none; }
  #list .del { color: #b4746b; background: none; border: none; padding: 4px 6px; font-size: 12px; }
  #list .del:hover { color: #ff9c8f; }
  footer { margin-top: 34px; font-size: 11.5px; color: var(--ink-dim); line-height: 1.8; text-align: center; }
  .empty { color: var(--ink-dim); font-size: 12.5px; padding: 14px 2px; }
</style>
</head>
<body>
<div class="shell">
  <header>
    <div class="logo">♪</div>
    <div>
      <h1>千千静听<span>WI-FI 传歌</span></h1>
      <p class="sub">电脑或手机连同一个 Wi-Fi，把歌拖进来就会落进手机曲库</p>
    </div>
  </header>

  <label id="drop" class="drop" for="file">
    <input id="file" type="file" multiple accept=".mp3,.m4a,.aac,.flac,.wav,.aif,.aiff,.caf,.lrc,.txt,audio/*">
    <div class="drop-icon">⇪</div>
    <strong>点击选歌，或把文件拖到这里</strong>
    <span>支持 MP3 / FLAC / M4A / WAV / AAC；歌词请用同名 .lrc 一起上传</span>
  </label>

  <ul id="queue" class="queue"></ul>

  <section class="files">
    <div class="files-head">
      <h2>手机曲库</h2>
      <button id="refresh" type="button">刷新</button>
    </div>
    <ul id="list"><li class="empty">正在读取…</li></ul>
  </section>

  <footer>传输过程中请保持这个页面打开。<br>传完回到手机，播放列表会自动刷新。</footer>
</div>

<script>
(function () {
  const drop = document.getElementById('drop');
  const input = document.getElementById('file');
  const queue = document.getElementById('queue');
  const list = document.getElementById('list');
  const refresh = document.getElementById('refresh');

  function humanSize(bytes) {
    if (!bytes) return '';
    const mb = bytes / (1024 * 1024);
    if (mb >= 1) return mb.toFixed(1) + ' MB';
    return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  }

  ['dragenter', 'dragover'].forEach(function (name) {
    document.addEventListener(name, function (event) {
      event.preventDefault();
      drop.classList.add('hot');
    });
  });
  ['dragleave', 'drop'].forEach(function (name) {
    document.addEventListener(name, function (event) {
      event.preventDefault();
      drop.classList.remove('hot');
    });
  });
  document.addEventListener('drop', function (event) {
    if (event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files.length) {
      send(event.dataTransfer.files);
    }
  });

  input.addEventListener('change', function () {
    if (input.files && input.files.length) {
      send(input.files);
      input.value = '';
    }
  });

  function send(files) {
    for (let i = 0; i < files.length; i++) {
      uploadOne(files[i]);
    }
  }

  function uploadOne(file) {
    const item = document.createElement('li');
    item.innerHTML = '<div class="name"><b></b><i>' + humanSize(file.size) + '</i></div><div class="bar"><div></div></div>';
    item.querySelector('b').textContent = file.name;
    const bar = item.querySelector('.bar > div');
    queue.appendChild(item);

    const form = new FormData();
    form.append('file', file, file.name);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/upload');
    xhr.upload.onprogress = function (event) {
      if (event.lengthComputable) {
        bar.style.width = Math.round(event.loaded / event.total * 100) + '%';
      }
    };
    xhr.onload = function () {
      bar.style.width = '100%';
      let result = null;
      try { result = JSON.parse(xhr.responseText); } catch (error) {}
      if (xhr.status === 200 && result && result.ok) {
        item.querySelector('.name i').innerHTML = '<span class="ok">✓ 已保存</span>';
        loadFiles();
      } else {
        const message = result && result.message ? result.message : '上传失败';
        item.querySelector('.name i').innerHTML = '<span class="bad">' + message + '</span>';
      }
      setTimeout(function () {
        if (item.parentNode) item.parentNode.removeChild(item);
      }, 6000);
    };
    xhr.onerror = function () {
      item.querySelector('.name i').innerHTML = '<span class="bad">网络中断</span>';
    };
    xhr.send(form);
  }

  function loadFiles() {
    fetch('/api/files')
      .then(function (response) { return response.json(); })
      .then(function (data) {
        const files = (data && data.files) || [];
        if (!files.length) {
          list.innerHTML = '<li class="empty">曲库还是空的，先传一首吧</li>';
          return;
        }
        list.innerHTML = '';
        files.forEach(function (entry, index) {
          const row = document.createElement('li');
          const ordinal = document.createElement('span');
          ordinal.className = 'idx';
          ordinal.textContent = String(index + 1).padStart(2, '0');
          const title = document.createElement('span');
          title.className = 'title';
          title.textContent = entry.name;
          const size = document.createElement('span');
          size.className = 'size';
          size.textContent = humanSize(entry.size);
          row.appendChild(ordinal);
          row.appendChild(title);
          row.appendChild(size);
          if (!/\.lrc$|\.txt$/i.test(entry.name)) {
            const del = document.createElement('button');
            del.className = 'del';
            del.type = 'button';
            del.textContent = '删除';
            del.addEventListener('click', function () {
              if (!confirm('从手机曲库删除「' + entry.name + '」？')) return;
              fetch('/delete?name=' + encodeURIComponent(entry.name), { method: 'POST' })
                .then(loadFiles)
                .catch(loadFiles);
            });
            row.appendChild(del);
          }
          list.appendChild(row);
        });
      })
      .catch(function () {
        list.innerHTML = '<li class="empty">读取失败</li>';
      });
  }

  refresh.addEventListener('click', loadFiles);
  loadFiles();
})();
</script>
</body>
</html>
"""#
}
