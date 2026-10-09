/* =================================================================
   Lite Arcade — 站点交互（零依赖）
   1. 开源游戏目录：按来源筛选 / 关键词搜索 / 排序
   2. GitHub Trending：运行时拉取 GitHub Search API，失败时回退到快照
   3. 页脚年份、深浅色跟随系统
   ================================================================= */
(function () {
  'use strict';

  var REL_BASE = (function () {
    // 依据当前路径推断站点根，兼容根路径与子目录部署（如 /lite-arcade/）
    var p = location.pathname;
    // 游戏二级页（/games/<slug>/）需要上溯两级，其余带 /games/ 或 /about/ 的页面上溯一级
    if (/\/games\/[^/]+\/?$/.test(p)) return '../../';
    if (p.indexOf('/games/') !== -1) return '../';
    if (p.indexOf('/about/') !== -1) return '../';
    return './';
  })();

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function fmtStars(n) {
    if (n == null) return null;
    return n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(n);
  }

  /* ----------------------------- 开源游戏目录 ----------------------------- */
  function renderCards(grid, items) {
    grid.textContent = '';
    if (!items.length) {
      var empty = el('p', 'source-line', '没有匹配的项目，试试更换来源或关键词。');
      grid.appendChild(empty);
      return;
    }
    var frag = document.createDocumentFragment();
    items.forEach(function (it) {
      var card = el('article', 'card');

      var thumb = el('div', 'card-thumb');
      thumb.setAttribute('aria-hidden', 'true');
      thumb.textContent = it.source === 'itchio' ? '🎮'
        : it.source === 'github' ? '⭐'
          : it.source === 'ludumdare' ? '🏆' : '📘';
      card.appendChild(thumb);

      var body = el('div', 'card-body');
      var h = el('h3');
      var a = el('a', null, it.name);
      a.href = it.url;
      a.rel = 'noopener nofollow external';
      a.target = '_blank';
      h.appendChild(a);
      body.appendChild(h);
      body.appendChild(el('p', null, it.desc));

      var meta = el('div', 'card-meta');
      var srcLabel = it.source === 'itchio' ? 'itch.io'
        : it.source === 'github' ? 'GitHub'
          : it.source === 'ludumdare' ? 'Ludum Dare' : 'SGT';
      meta.appendChild(el('span', 'tag tag-src', srcLabel));
      if (it.lang) meta.appendChild(el('span', 'tag', it.lang));
      if (it.stars != null) meta.appendChild(el('span', 'tag tag-star', '★ ' + fmtStars(it.stars)));
      (it.tags || []).slice(0, 2).forEach(function (t) { meta.appendChild(el('span', 'tag', t)); });
      body.appendChild(meta);

      card.appendChild(body);
      frag.appendChild(card);
    });
    grid.appendChild(frag);
  }

  function initCatalog() {
    var grid = document.getElementById('catalog-grid');
    if (!grid) return;
    var status = document.getElementById('catalog-count');
    var chips = Array.prototype.slice.call(document.querySelectorAll('[data-filter-source]'));
    var search = document.getElementById('catalog-search');

    var state = { source: 'all', kw: '' };

    fetch(REL_BASE + 'assets/data/sources.json')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var items = data.items || [];
        if (status) status.textContent = '共收录 ' + items.length + ' 个开源项目（数据快照：' + data.fetchedAt + '）';

        function apply() {
          var out = items.filter(function (it) {
            if (state.source !== 'all' && it.source !== state.source) return false;
            if (!state.kw) return true;
            var hay = (it.name + ' ' + it.desc + ' ' + (it.tags || []).join(' ') + ' ' + (it.lang || '')).toLowerCase();
            return hay.indexOf(state.kw.toLowerCase()) !== -1;
          });
          out.sort(function (a, b) { return (b.stars || 0) - (a.stars || 0); });
          renderCards(grid, out);
        }

        chips.forEach(function (chip) {
          chip.addEventListener('click', function () {
            state.source = chip.getAttribute('data-filter-source');
            chips.forEach(function (c) {
              c.setAttribute('aria-pressed', String(c === chip));
            });
            apply();
          });
        });

        if (search) {
          search.addEventListener('input', function () {
            state.kw = search.value.trim();
            apply();
          });
        }

        apply();
      })
      .catch(function () {
        if (grid) grid.textContent = '目录数据加载失败，请确认 assets/data/sources.json 可访问。';
      });
  }

  /* --------------------------- GitHub Trending --------------------------- */
  var TRENDING_FALLBACK = [
    { name: 'pixijs/pixijs', url: 'https://github.com/pixijs/pixijs', desc: '2D WebGL 渲染引擎', stars: 48318 },
    { name: '4ian/GDevelop', url: 'https://github.com/4ian/GDevelop', desc: '无代码跨平台游戏引擎', stars: 27309 },
    { name: 'gabrielecirulli/2048', url: 'https://github.com/gabrielecirulli/2048', desc: '经典 2048 官方源码', stars: 13418 },
    { name: 'replit/kaboom', url: 'https://github.com/replit/kaboom', desc: '极简 JavaScript 游戏库', stars: 2735 }
  ];

  function renderTrending(list, live) {
    var box = document.getElementById('trending-list');
    if (!box) return;
    box.textContent = '';
    list.slice(0, 6).forEach(function (r) {
      var row = el('article', 'card');
      var body = el('div', 'card-body');
      var h = el('h3');
      var a = el('a', null, r.name);
      a.href = r.url; a.target = '_blank'; a.rel = 'noopener nofollow external';
      h.appendChild(a);
      body.appendChild(h);
      body.appendChild(el('p', null, r.desc));
      var meta = el('div', 'card-meta');
      meta.appendChild(el('span', 'tag tag-src', 'GitHub'));
      if (r.stars != null) meta.appendChild(el('span', 'tag tag-star', '★ ' + fmtStars(r.stars)));
      body.appendChild(meta);
      row.appendChild(body);
      box.appendChild(row);
    });
    var note = document.getElementById('trending-note');
    if (note) {
      note.textContent = live
        ? '实时数据 · 来源：GitHub Search API（topic:game，近 90 天有提交，按 star 排序）'
        : '离线快照 · 实时接口不可用时使用内置快照';
    }
  }

  function initTrending() {
    var box = document.getElementById('trending-list');
    if (!box) return;
    renderTrending(TRENDING_FALLBACK, false);

    var since = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);
    var url = 'https://api.github.com/search/repositories?q=topic:game+pushed:>' + since +
      '&sort=stars&order=desc&per_page=6';

    var ctrl = ('AbortController' in window) ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 6000);

    fetch(url, { signal: ctrl ? ctrl.signal : undefined, headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (j) {
        clearTimeout(timer);
        var list = (j.items || []).map(function (r) {
          return {
            name: r.full_name,
            url: r.html_url,
            desc: (r.description || 'GitHub 开源游戏仓库').slice(0, 90),
            stars: r.stargazers_count
          };
        });
        if (list.length) renderTrending(list, true);
      })
      .catch(function () { clearTimeout(timer); });
  }

  /* ------------------------------- 杂项 ------------------------------- */
  function initMisc() {
    var y = document.getElementById('year');
    if (y) y.textContent = String(new Date().getFullYear());
  }

  function ready(fn) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  ready(function () {
    initCatalog();
    initTrending();
    initMisc();
  });
})();
