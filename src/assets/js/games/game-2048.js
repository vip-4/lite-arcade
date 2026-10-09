/* 2048 — 原生 Canvas 实现，零依赖 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  var N = 4, SIZE = 460, PAD = 10, GAP = 10;
  var CELL = (SIZE - PAD * 2 - GAP * (N - 1)) / N;

  var COLORS = {
    2: '#eee4da', 4: '#ede0c8', 8: '#f2b179', 16: '#f59563', 32: '#f67c5f',
    64: '#f65e3b', 128: '#edcf72', 256: '#edcc61', 512: '#edc850',
    1024: '#edc53f', 2048: '#edc22e'
  };
  var TEXT = { 2: '#4a4038', 4: '#4a4038' };

  function emptyCells(g) {
    var out = [];
    for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) if (!g[y][x]) out.push({ x: x, y: y });
    return out;
  }
  function addRandom(grid) {
    var free = emptyCells(grid);
    if (!free.length) return false;
    var p = free[Math.floor(Math.random() * free.length)];
    grid[p.y][p.x] = Math.random() < 0.9 ? 2 : 4;
    return true;
  }
  function canMove(grid) {
    for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) {
      var v = grid[y][x];
      if (!v) return true;
      if (x + 1 < N && grid[y][x + 1] === v) return true;
      if (y + 1 < N && grid[y + 1][x] === v) return true;
    }
    return false;
  }
  /** 压缩一行：返回 [新行, 本次得分] */
  function slide(line) {
    var arr = line.filter(function (v) { return v; });
    var out = [], score = 0, i;
    for (i = 0; i < arr.length; i++) {
      if (i + 1 < arr.length && arr[i] === arr[i + 1]) { out.push(arr[i] * 2); score += arr[i] * 2; i++; }
      else out.push(arr[i]);
    }
    while (out.length < N) out.push(0);
    return [out, score];
  }

  Arcade.create({
    canvas: canvas,
    width: SIZE,
    height: SIZE,
    storageKey: 'lite-arcade:2048',

    reset: function () {
      var grid = [], y, x;
      for (y = 0; y < N; y++) { grid.push([]); for (x = 0; x < N; x++) grid[y].push(0); }
      addRandom(grid); addRandom(grid);
      return { grid: grid, won: false };
    },

    onSwipe: function (g, dir) { move(g, dir); },

    update: function () { /* 回合制，无需逐帧逻辑 */ },

    draw: function (g, ctx) {
      ctx.fillStyle = '#05070f';
      ctx.fillRect(0, 0, SIZE, SIZE);
      var s = g.state;
      if (!s) return;
      var grid = s.grid;

      ctx.fillStyle = '#141c33';
      Arcade.roundRect(ctx, 0, 0, SIZE, SIZE, 12);
      ctx.fill();

      for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) {
        var v = grid[y][x];
        var px = PAD + x * (CELL + GAP), py = PAD + y * (CELL + GAP);
        ctx.fillStyle = v ? (COLORS[v] || '#3c3a32') : 'rgba(255,255,255,.045)';
        Arcade.roundRect(ctx, px, py, CELL, CELL, 8);
        ctx.fill();
        if (v) {
          var size = v < 100 ? 34 : (v < 1000 ? 29 : 24);
          Arcade.centerText(ctx, String(v), px + CELL / 2, py + CELL / 2, size, TEXT[v] || '#f9f6f2', 800);
        }
      }
    }
  });

  function move(g, dir) {
    var s = g.state;
    if (!s || g.over) return;
    var grid = s.grid, gained = 0, changed = false, y, x, line, res;

    function get(x, y) { return grid[y][x]; }
    function set(x, y, v) { grid[y][x] = v; }

    for (var i = 0; i < N; i++) {
      var coords = [], j;
      for (j = 0; j < N; j++) {
        coords.push(dir === 'left' ? { x: j, y: i }
          : dir === 'right' ? { x: N - 1 - j, y: i }
            : dir === 'up' ? { x: i, y: j }
              : { x: i, y: N - 1 - j });
      }
      line = coords.map(function (c) { return get(c.x, c.y); });
      res = slide(line);
      for (j = 0; j < N; j++) {
        var c = coords[j];
        if (get(c.x, c.y) !== res[0][j]) changed = true;
        set(c.x, c.y, res[0][j]);
      }
      gained += res[1];
    }

    if (!changed) return false;
    g.addScore(gained);
    addRandom(grid);

    for (y = 0; y < N; y++) for (x = 0; x < N; x++) {
      if (grid[y][x] === 2048 && !s.won) {
        s.won = true;
        g.showOverlay('达成 2048！', '你已经拼出 2048，可继续挑战更高分数。当前得分 ' + g.score + '。');
        g.paused = true;
        return true;
      }
    }
    if (!canMove(grid)) { g.gameOver('棋盘已满且无法合并。'); }
    return true;
  }
})();
