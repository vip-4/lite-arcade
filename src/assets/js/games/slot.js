/* 幸运老虎机 · 数据驱动引擎（5 主题共用）
   经 game-core.js 内核统一入口 Arcade.create() 挂载；所有符号、赔率、配色、赔付线、
   免费旋转规则均来自页面 <script id="slot-theme-data"> 的 THEME 对象，引擎零硬编码。
   新增主题 = 在 games.json 增加一条 slot.* 配置，无需改动本文件。 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  /* 默认主题（兜底，正常由页面主题 JSON 覆盖） */
  var DEFAULT_THEME = {
    id: 'slot-classic', name: '经典幸运7', width: 500, height: 330,
    startBalance: 1000, betLevels: [10, 20, 50, 100],
    freeSpinsNeeded: 3, freeSpinsCount: 8, freeSpinMult: 2,
    palette: { bg: '#070b16', reel: 'rgba(110,231,255,.35)', win: '#ff6ec7', text: '#fff' },
    symbols: [
      { id: 'cherry',  icon: '🍒', alt: '樱桃',  weight: 22, pay: { 2: 2, 3: 5 } },
      { id: 'lemon',   icon: '🍋', alt: '柠檬',  weight: 20, pay: { 3: 8 } },
      { id: 'grape',   icon: '🍇', alt: '葡萄',  weight: 18, pay: { 3: 10 } },
      { id: 'bell',    icon: '🔔', alt: '铃铛',  weight: 12, pay: { 3: 20 } },
      { id: 'seven',   icon: '7️⃣', alt: '幸运7', weight: 6,  pay: { 3: 100 } },
      { id: 'wild',    icon: '⭐', alt: '万能',  weight: 6,  pay: { 3: 50 }, wild: true },
      { id: 'scatter', icon: '💎', alt: '钻石',  weight: 5,  pay: { 3: 5 }, scatter: true }
    ],
    paylines: [ [1,1,1,1,1], [0,0,0,0,0], [2,2,2,2,2], [0,1,2,1,0], [2,1,0,1,2] ]
  };

  function loadTheme() {
    var el = document.getElementById('slot-theme-data');
    if (el && el.textContent && el.textContent.trim()) {
      try { var t = JSON.parse(el.textContent); if (t && t.symbols) return t; } catch (e) {}
    }
    return DEFAULT_THEME;
  }

  var T = loadTheme();
  var SYMS = T.symbols;
  var REELS = T.reels || 5, ROWS = T.rows || 3;
  var W = T.width || 500, H = T.height || 330, M = 14;
  var cw = (W - M * 2) / REELS, ch = (H - M * 2) / ROWS;
  var PAL = T.palette || { bg: '#070b16', reel: 'rgba(110,231,255,.35)', win: '#ff6ec7', text: '#fff' };

  var WILD = -1, SCAT = -1;
  SYMS.forEach(function (s, i) { if (s.wild) WILD = i; if (s.scatter) SCAT = i; });
  function isWild(i) { return i === WILD; }
  function isScat(i) { return i === SCAT; }

  function weightedPick() {
    var total = 0, i;
    for (i = 0; i < SYMS.length; i++) total += SYMS[i].weight;
    var r = Math.random() * total;
    for (i = 0; i < SYMS.length; i++) { r -= SYMS[i].weight; if (r <= 0) return i; }
    return SYMS.length - 1;
  }
  function spinReel() { var a = []; for (var r = 0; r < ROWS; r++) a.push(weightedPick()); return a; }

  var betEl = document.querySelector('[data-hud="bet"]');
  var winEl = document.querySelector('[data-hud="win"]');
  var spinEl = document.querySelector('[data-hud="spins"]');
  var liveEl = document.getElementById('slot-live');
  function setBet(v) { if (betEl) betEl.textContent = v; }
  function setWin(v) { if (winEl) winEl.textContent = v; }
  function setSpins(v) { if (spinEl) spinEl.textContent = v; }
  function say(t) { if (liveEl) liveEl.textContent = t; }

  var S = null, auto = false, muted = true, audioCtx = null;
  var KEY = 'lite-arcade:slot:' + (T.id || 'x');

  function loadStats() { try { return JSON.parse(localStorage.getItem(KEY + ':stats') || '{}'); } catch (e) { return {}; } }
  function saveStats(s) { try { localStorage.setItem(KEY + ':stats', JSON.stringify(s)); } catch (e) {} }

  function reset() {
    S = {
      visible: [], spinning: false, spinT: 0, stopAt: [], done: [],
      betIndex: 0, balance: T.startBalance || 1000, lastWin: 0,
      freeActive: false, freeLeft: 0, flash: [], status: '点击「转动」开始下注', flick: 0
    };
    for (var r = 0; r < REELS; r++) S.visible.push(spinReel());
    setBet(T.betLevels[S.betIndex]); setWin(0); setSpins(0);
    return S;
  }
  function curBet() { return T.betLevels[S.betIndex]; }

  function beep(freq, dur) {
    if (muted) return;
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      var o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.frequency.value = freq; o.type = 'sine'; o.connect(g); g.connect(audioCtx.destination);
      g.gain.setValueAtTime(0.04, audioCtx.currentTime);
      g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + dur);
      o.start(); o.stop(audioCtx.currentTime + dur);
    } catch (e) {}
  }

  function startSpin() {
    if (S.spinning) return;
    var isFree = S.freeActive;
    if (!isFree) {
      if (S.balance < curBet()) { game.gameOver('余额不足，游戏结束。'); return; }
      S.balance -= curBet(); game.setScore(S.balance);
    } else { S.freeLeft--; }
    S.spinning = true; S.spinT = 0; S.flash = []; S.stopAt = []; S.done = [];
    for (var r = 0; r < REELS; r++) { S.stopAt.push(700 + r * 220); S.done.push(false); }
    S.status = isFree ? ('免费旋转剩余 ' + (S.freeLeft + 1)) : '转动中…';
    game.hideOverlay(); beep(440, 0.05);
  }

  function evaluate() {
    var g = [];
    for (var reel = 0; reel < REELS; reel++) { g[reel] = []; for (var row = 0; row < ROWS; row++) g[reel][row] = S.visible[reel][row]; }
    var gt = [];
    for (var rr = 0; rr < ROWS; rr++) { gt[rr] = []; for (var rl = 0; rl < REELS; rl++) gt[rr][rl] = g[rl][rr]; }

    var total = 0, winLines = [];
    (T.paylines || []).forEach(function (line, li) {
      var ids = []; for (var i = 0; i < REELS; i++) ids.push(gt[line[i]][i]);
      var base = null, count = 0;
      for (i = 0; i < REELS; i++) {
        var s = ids[i];
        if (isWild(s)) { count++; continue; }
        if (base === null) { base = s; count++; continue; }
        if (s === base) { count++; continue; }
        break;
      }
      if (base === null) base = WILD;
      var sym = SYMS[base];
      var key = count >= 3 ? 3 : (count === 2 ? 2 : 0);
      if (sym.pay && sym.pay[key]) { total += curBet() * sym.pay[key]; winLines.push(li); }
    });

    var scat = 0;
    for (rr = 0; rr < ROWS; rr++) for (rl = 0; rl < REELS; rl++) if (isScat(gt[rr][rl])) scat++;
    if (scat >= (T.freeSpinsNeeded || 3)) {
      var sp = (SYMS[SCAT].pay && SYMS[SCAT].pay[3]) ? SYMS[SCAT].pay[3] : 5;
      total += curBet() * sp;
      if (!S.freeActive) { S.freeActive = true; S.freeLeft = T.freeSpinsCount || 8; S.status = '触发 ' + (T.freeSpinsCount || 8) + ' 次免费旋转！'; }
    }

    if (S.freeActive) total *= (T.freeSpinMult || 2);
    S.lastWin = total;
    if (total > 0) { S.balance += total; game.setScore(S.balance); }
    setWin(total); S.flash = winLines; S.spinning = false;

    var st = loadStats();
    st.spins = (st.spins || 0) + 1;
    if (total > (st.bestWin || 0)) st.bestWin = total;
    if (S.freeActive && scat >= (T.freeSpinsNeeded || 3)) st.freeHits = (st.freeHits || 0) + 1;
    saveStats(st); setSpins(st.spins);

    say(total > 0 ? ('中奖 ' + total + '！') : '未中奖，再试一次');
    beep(total > 0 ? 660 : 220, total > 0 ? 0.12 : 0.06);

    if (S.freeActive) {
      if (S.freeLeft > 0) { S.status = '免费旋转剩余 ' + S.freeLeft; setTimeout(startSpin, 850); }
      else { S.freeActive = false; S.status = '免费旋转结束，继续下注'; }
    } else if (S.balance < (T.betLevels[0] || 10)) {
      game.gameOver('余额不足，游戏结束。');
    } else {
      S.status = '点击「转动」继续下注';
      if (auto) setTimeout(startSpin, 600);
    }
  }

  var game = Arcade.create({
    canvas: canvas, width: W, height: H, storageKey: KEY,
    reset: function () { return reset(); },
    onTap: function () { if (!S.spinning) startSpin(); },
    onKey: function (g, k) {
      if (k === 'Enter') { if (!S.spinning) startSpin(); }
      else if ((k === 'b' || k === 'B') && !S.spinning && !S.freeActive) {
        S.betIndex = (S.betIndex + 1) % T.betLevels.length; setBet(curBet());
      }
    },
    update: function (g, dt) {
      if (!S.spinning) return;
      S.spinT += dt; S.flick += dt;
      for (var r = 0; r < REELS; r++) {
        if (S.done[r]) continue;
        if (S.spinT >= S.stopAt[r]) { S.visible[r] = spinReel(); S.done[r] = true; }
        else if (S.flick > 50) { S.visible[r] = spinReel(); }
      }
      S.flick = S.flick > 50 ? 0 : S.flick;
      if (S.done.indexOf(false) === -1) evaluate();
    },
    draw: function (g, ctx) {
      ctx.fillStyle = PAL.bg; ctx.fillRect(0, 0, W, H);
      for (var r = 0; r < REELS; r++) {
        var x = M + r * cw;
        Arcade.roundRect(ctx, x + 3, M - 2, cw - 6, H - 2 * M + 4, 10);
        ctx.fillStyle = 'rgba(110,231,255,.04)'; ctx.fill();
        ctx.strokeStyle = PAL.reel; ctx.lineWidth = 1.5; ctx.stroke();
        for (var row = 0; row < ROWS; row++) {
          var y = M + row * ch, sy = S.visible[r][row];
          var onLine = S.flash.some(function (li) { return T.paylines[li][r] === row; });
          if (onLine) { ctx.save(); ctx.shadowColor = PAL.win; ctx.shadowBlur = 16; }
          Arcade.centerText(ctx, SYMS[sy].icon, x + cw / 2, y + ch / 2, Math.min(cw, ch) * 0.5, PAL.text, 400);
          if (onLine) ctx.restore();
        }
      }
      Arcade.centerText(ctx, S.status, W / 2, H - 8, 13, PAL.text, 700);
    }
  });

  function bind(sel, fn) {
    var b = document.querySelector(sel);
    if (!b) return;
    b.addEventListener('click', function (e) {
      e.preventDefault();
      if (!game.running) game.start();
      fn();
    });
  }
  bind('[data-slot="spin"]',     function () { if (!S.spinning) startSpin(); });
  bind('[data-slot="bet"]',      function () { if (!S.spinning && !S.freeActive) { S.betIndex = (S.betIndex + 1) % T.betLevels.length; setBet(curBet()); } });
  bind('[data-slot="maxbet"]',   function () { if (!S.spinning && !S.freeActive) { S.betIndex = T.betLevels.length - 1; setBet(curBet()); } });
  bind('[data-slot="autospin"]', function () { auto = !auto; var b = document.querySelector('[data-slot="autospin"]'); if (b) b.textContent = auto ? '停止' : '自动'; if (auto && !S.spinning) startSpin(); });
  bind('[data-slot="mute"]',     function () { muted = !muted; var b = document.querySelector('[data-slot="mute"]'); if (b) b.textContent = muted ? '🔇' : '🔊'; if (!muted) beep(520, 0.05); });

  window.SlotEngine = { mount: function () { /* 主题由页面 JSON 驱动，已自动挂载 */ } };
})();
