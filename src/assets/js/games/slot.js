/* 幸运老虎机 Slot Machine — 原生 Canvas 实现，零依赖
   复用 game-core.js 内核：统一入口 Arcade.create()，与全站游戏架构一致。
   核心机制：5 转轮 × 3 行、5 条赔付线、加权随机转轮、Wild/Scatter 特殊符号、
   3 个 Scatter 触发免费旋转。所有参数集中在 CONFIG，便于后续调整。 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  /* ============================ 参数配置（可调） ============================ */
  var CONFIG = {
    reels: 5,
    rows: 3,
    startBalance: 1000,
    betLevels: [10, 20, 50, 100],
    minBet: 10,
    freeSpinsNeeded: 3,     // 任意位置出现 3 个 Scatter 触发
    freeSpinsCount: 8,
    freeSpinMult: 2,        // 免费旋转期间所有奖金翻倍
    // 符号表：weight=出现权重，pay=按赔付线命中数 × 注额 的倍率
    symbols: [
      { id: 'cherry',  icon: '🍒', weight: 22, pay: { 2: 2, 3: 5 } },
      { id: 'lemon',   icon: '🍋', weight: 20, pay: { 3: 8 } },
      { id: 'grape',   icon: '🍇', weight: 18, pay: { 3: 10 } },
      { id: 'bell',    icon: '🔔', weight: 12, pay: { 3: 20 } },
      { id: 'seven',   icon: '7️⃣', weight: 6,  pay: { 3: 100 } },
      { id: 'wild',    icon: '⭐', weight: 6,  pay: { 3: 50 }, wild: true },
      { id: 'scatter', icon: '💎', weight: 5,  pay: { 3: 5 }, scatter: true }
    ],
    // 5 条赔付线：每项为 5 个转轮各自取第几行（0=上,1=中,2=下）
    paylines: [
      [1, 1, 1, 1, 1],
      [0, 0, 0, 0, 0],
      [2, 2, 2, 2, 2],
      [0, 1, 2, 1, 0],
      [2, 1, 0, 1, 2]
    ]
  };

  var W = 500, H = 330, M = 14; // 逻辑尺寸与边距
  var cw = (W - M * 2) / CONFIG.reels;   // 单列宽
  var ch = (H - M * 2) / CONFIG.rows;    // 单行高

  function symIndex(id) { for (var i = 0; i < CONFIG.symbols.length; i++) if (CONFIG.symbols[i].id === id) return i; return 0; }
  var WILD = symIndex('wild'), SCAT = symIndex('scatter');

  // 加权随机取一个符号下标
  function weightedPick() {
    var total = 0, i;
    for (i = 0; i < CONFIG.symbols.length; i++) total += CONFIG.symbols[i].weight;
    var r = Math.random() * total;
    for (i = 0; i < CONFIG.symbols.length; i++) { r -= CONFIG.symbols[i].weight; if (r <= 0) return i; }
    return CONFIG.symbols.length - 1;
  }
  // 一个转轮可见的 3 个符号（上/中/下）
  function spinReel() { return [weightedPick(), weightedPick(), weightedPick()]; }

  /* ============================ HUD 元素 ============================ */
  var betEl = document.querySelector('[data-hud="bet"]');
  var winEl = document.querySelector('[data-hud="win"]');
  function setBet(v) { if (betEl) betEl.textContent = v; }
  function setWin(v) { if (winEl) winEl.textContent = v; }

  /* ============================ 状态 ============================ */
  var S = null;
  function reset() {
    S = {
      visible: [],            // [reel][row] = 符号下标
      spinning: false,
      spinT: 0,
      stopAt: [],
      done: [],
      betIndex: 1,
      balance: CONFIG.startBalance,
      lastWin: 0,
      freeActive: false,
      freeLeft: 0,
      flash: [],              // 中奖赔付线索引
      status: '点击转盘开始下注',
      flick: 0
    };
    for (var r = 0; r < CONFIG.reels; r++) S.visible.push(spinReel());
    setBet(CONFIG.betLevels[S.betIndex]);
    setWin(0);
    return S;
  }

  function curBet() { return CONFIG.betLevels[S.betIndex]; }

  /* ============================ 转轮与中奖判定 ============================ */
  function startSpin() {
    if (S.spinning) return;
    var isFree = S.freeActive;
    if (!isFree) {
      if (S.balance < curBet()) { game.gameOver('余额不足，游戏结束。'); return; }
      S.balance -= curBet();
      game.setScore(S.balance);
    } else {
      S.freeLeft--;
    }
    S.spinning = true; S.spinT = 0; S.flash = [];
    S.stopAt = []; S.done = [];
    for (var r = 0; r < CONFIG.reels; r++) { S.stopAt.push(700 + r * 220); S.done.push(false); }
    S.status = isFree ? ('免费旋转剩余 ' + (S.freeLeft + 1)) : '转动中…';
    game.hideOverlay();
  }

  function evaluate() {
    var grid = S.visible; // grid[row][reel]
    var g = [[], [], []];
    for (var reel = 0; reel < CONFIG.reels; reel++)
      for (var row = 0; row < CONFIG.rows; row++) g[row][reel] = grid[reel][row];

    var total = 0, winLines = [];

    // 逐赔付线判定（Wild 可替代除 Scatter 外的任意符号）
    CONFIG.paylines.forEach(function (line, li) {
      var ids = []; for (var i = 0; i < CONFIG.reels; i++) ids.push(g[line[i]][i]);
      var base = null, count = 0;
      for (i = 0; i < CONFIG.reels; i++) {
        var s = ids[i];
        if (s === WILD) { count++; continue; }
        if (base === null) { base = s; count++; continue; }
        if (s === base) { count++; continue; }
        break;
      }
      if (base === null) base = WILD; // 全 Wild
      var sym = CONFIG.symbols[base];
      var key = count >= 3 ? 3 : (count === 2 ? 2 : 0);
      if (sym.pay && sym.pay[key]) {
        total += curBet() * sym.pay[key];
        winLines.push(li);
      }
    });

    // Scatter：全盘任意位置出现 3+ 触发免费旋转并单独派彩
    var scat = 0;
    for (var rr = 0; rr < CONFIG.rows; rr++) for (var rl = 0; rl < CONFIG.reels; rl++)
      if (g[rr][rl] === SCAT) scat++;
    if (scat >= CONFIG.freeSpinsNeeded) {
      total += curBet() * CONFIG.symbols[SCAT].pay[3];
      if (!S.freeActive) { S.freeActive = true; S.freeLeft = CONFIG.freeSpinsCount; S.status = '触发 ' + CONFIG.freeSpinsCount + ' 次免费旋转！'; }
    }

    if (S.freeActive) total *= CONFIG.freeSpinMult;
    S.lastWin = total;
    if (total > 0) { S.balance += total; game.setScore(S.balance); }
    setWin(total);
    S.flash = winLines;
    S.spinning = false;

    if (S.freeActive) {
      if (S.freeLeft > 0) { S.status = '免费旋转剩余 ' + S.freeLeft; setTimeout(startSpin, 850); }
      else { S.freeActive = false; S.status = '免费旋转结束，继续下注'; }
    } else if (S.balance < CONFIG.minBet) {
      game.gameOver('余额不足，游戏结束。');
    } else {
      S.status = '点击转盘继续下注';
    }
  }

  /* ============================ 内核接口 ============================ */
  var game = Arcade.create({
    canvas: canvas, width: W, height: H, storageKey: 'lite-arcade:slot',
    reset: function () { return reset(); },

    onTap: function () { if (!S.spinning) startSpin(); },
    onKey: function (g, k) {
      if (k === 'Enter') { if (!S.spinning) startSpin(); }
      else if ((k === 'b' || k === 'B') && !S.spinning && !S.freeActive) {
        S.betIndex = (S.betIndex + 1) % CONFIG.betLevels.length; setBet(curBet());
      }
    },

    update: function (g, dt) {
      if (!S.spinning) return;
      S.spinT += dt; S.flick += dt;
      for (var r = 0; r < CONFIG.reels; r++) {
        if (S.done[r]) continue;
        if (S.spinT >= S.stopAt[r]) { S.visible[r] = spinReel(); S.done[r] = true; }
        else if (S.flick > 50) { S.visible[r] = spinReel(); } // 转动闪烁
      }
      S.flick = S.flick > 50 ? 0 : S.flick;
      if (S.done.indexOf(false) === -1) evaluate();
    },

    draw: function (g, ctx) {
      ctx.fillStyle = '#070b16'; ctx.fillRect(0, 0, W, H);
      // 转轮框
      for (var r = 0; r < CONFIG.reels; r++) {
        var x = M + r * cw;
        Arcade.roundRect(ctx, x + 3, M - 2, cw - 6, H - 2 * M + 4, 10);
        ctx.fillStyle = 'rgba(110,231,255,.04)'; ctx.fill();
        ctx.strokeStyle = 'rgba(110,231,255,.35)'; ctx.lineWidth = 1.5; ctx.stroke();
        for (var row = 0; row < CONFIG.rows; row++) {
          var y = M + row * ch, sy = S.visible[r][row];
          var sx = x + cw / 2, syc = y + ch / 2;
          // 中奖高亮
          var onLine = S.flash.some(function (li) { return CONFIG.paylines[li][r] === row; });
          if (onLine) { ctx.save(); ctx.shadowColor = '#ff6ec7'; ctx.shadowBlur = 16; }
          Arcade.centerText(ctx, CONFIG.symbols[sy].icon, sx, syc, Math.min(cw, ch) * 0.5, '#fff', 400);
          if (onLine) ctx.restore();
        }
      }
      // 赔付线指示（中线）
      Arcade.centerText(ctx, S.status, W / 2, H - 8, 13, '#6ee7ff', 700);
    }
  });
})();
