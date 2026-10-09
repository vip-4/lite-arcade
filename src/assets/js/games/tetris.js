/* 俄罗斯方块 Tetris — 原生 Canvas 实现，零依赖 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  var COLS = 10, ROWS = 20, CELL = 30;
  var W = COLS * CELL, H = ROWS * CELL;

  var SHAPES = {
    I: [[0, 0, 0, 0], [1, 1, 1, 1], [0, 0, 0, 0], [0, 0, 0, 0]],
    J: [[1, 0, 0], [1, 1, 1], [0, 0, 0]],
    L: [[0, 0, 1], [1, 1, 1], [0, 0, 0]],
    O: [[1, 1], [1, 1]],
    S: [[0, 1, 1], [1, 1, 0], [0, 0, 0]],
    T: [[0, 1, 0], [1, 1, 1], [0, 0, 0]],
    Z: [[1, 1, 0], [0, 1, 1], [0, 0, 0]]
  };
  var COLORS = { I: '#6ee7ff', J: '#7c9cff', L: '#ffb066', O: '#ffd166', S: '#4ade80', T: '#a78bfa', Z: '#ff6b81' };
  var KEYS = Object.keys(SHAPES);

  function rotate(m) {
    var n = m.length, out = [], y, x;
    for (y = 0; y < n; y++) { out.push([]); for (x = 0; x < n; x++) out[y].push(m[n - 1 - x][y]); }
    return out;
  }

  function newPiece() {
    var k = KEYS[Math.floor(Math.random() * KEYS.length)];
    return { type: k, m: SHAPES[k].map(function (r) { return r.slice(); }), x: Math.floor((COLS - SHAPES[k].length) / 2), y: 0 };
  }

  function collides(grid, p) {
    for (var y = 0; y < p.m.length; y++) for (var x = 0; x < p.m[y].length; x++) {
      if (!p.m[y][x]) continue;
      var gx = p.x + x, gy = p.y + y;
      if (gx < 0 || gx >= COLS || gy >= ROWS) return true;
      if (gy >= 0 && grid[gy][gx]) return true;
    }
    return false;
  }

  Arcade.create({
    canvas: canvas,
    width: W,
    height: H,
    storageKey: 'lite-arcade:tetris',
    tick: 480,

    reset: function () {
      var grid = [], y, x;
      for (y = 0; y < ROWS; y++) { grid.push([]); for (x = 0; x < COLS; x++) grid[y].push(''); }
      return { grid: grid, piece: newPiece(), next: newPiece(), lines: 0 };
    },

    onSwipe: function (g, dir) {
      var s = g.state, p = s.piece;
      if (dir === 'left' || dir === 'right') {
        p.x += (dir === 'left' ? -1 : 1);
        if (collides(s.grid, p)) p.x -= (dir === 'left' ? -1 : 1);
      } else if (dir === 'up') {
        var r = rotate(p.m);
        var old = p.m; p.m = r;
        if (collides(s.grid, p)) p.m = old;
      } else if (dir === 'down') {
        g.addScore(1);
        step(g, true);
      }
    },

    onTap: function (g) {
      var s = g.state, p = s.piece, r = rotate(p.m), old = p.m;
      p.m = r;
      if (collides(s.grid, p)) p.m = old;
    },

    update: function (g) { step(g, false); },

    draw: function (g, ctx) {
      ctx.fillStyle = '#05070f';
      ctx.fillRect(0, 0, W, H);
      var s = g.state;
      if (!s) return;

      ctx.strokeStyle = 'rgba(110,231,255,.07)';
      ctx.lineWidth = 1;
      for (var x = 0; x <= COLS; x++) { ctx.beginPath(); ctx.moveTo(x * CELL, 0); ctx.lineTo(x * CELL, H); ctx.stroke(); }
      for (var y = 0; y <= ROWS; y++) { ctx.beginPath(); ctx.moveTo(0, y * CELL); ctx.lineTo(W, y * CELL); ctx.stroke(); }

      // 已落定的方块
      for (var ry = 0; ry < ROWS; ry++) for (var rx = 0; rx < COLS; rx++) {
        var v = s.grid[ry][rx];
        if (!v) continue;
        ctx.fillStyle = COLORS[v];
        Arcade.roundRect(ctx, rx * CELL + 1.5, ry * CELL + 1.5, CELL - 3, CELL - 3, 4);
        ctx.fill();
      }

      // 当前方块 + 落点预览
      var p = s.piece, ghost = { type: p.type, m: p.m, x: p.x, y: p.y };
      while (!collides(s.grid, { type: ghost.type, m: ghost.m, x: ghost.x, y: ghost.y + 1 })) ghost.y++;
      drawPiece(ctx, ghost, 'rgba(255,255,255,.10)');
      drawPiece(ctx, p, COLORS[p.type]);

      ctx.fillStyle = 'rgba(255,255,255,.5)';
      ctx.font = '600 13px -apple-system, "PingFang SC", sans-serif';
      ctx.textAlign = 'left';
      ctx.fillText('消行 ' + s.lines, 8, 18);
    }
  });

  function drawPiece(ctx, p, color) {
    for (var y = 0; y < p.m.length; y++) for (var x = 0; x < p.m[y].length; x++) {
      if (!p.m[y][x]) continue;
      ctx.fillStyle = color;
      Arcade.roundRect(ctx, (p.x + x) * CELL + 1.5, (p.y + y) * CELL + 1.5, CELL - 3, CELL - 3, 4);
      ctx.fill();
    }
  }

  function step(g, soft) {
    var s = g.state, p = s.piece;
    var ny = p.y + 1;
    if (!collides(s.grid, { type: p.type, m: p.m, x: p.x, y: ny })) {
      p.y = ny;
      return;
    }
    // 固定
    for (var y = 0; y < p.m.length; y++) for (var x = 0; x < p.m[y].length; x++) {
      if (p.m[y][x] && p.y + y >= 0) s.grid[p.y + y][p.x + x] = p.type;
    }
    // 消行
    var cleared = 0;
    for (var r = ROWS - 1; r >= 0; r--) {
      if (s.grid[r].every(function (c) { return !!c; })) {
        s.grid.splice(r, 1);
        var row = []; for (var i = 0; i < COLS; i++) row.push('');
        s.grid.unshift(row);
        cleared++; r++;
      }
    }
    if (cleared) {
      s.lines += cleared;
      g.addScore([0, 100, 300, 500, 800][cleared] || 800);
    } else if (!soft) {
      g.addScore(2);
    }

    s.piece = s.next;
    s.next = newPiece();
    if (collides(s.grid, s.piece)) g.gameOver('方块堆到顶了。共消除 ' + s.lines + ' 行。');
  }
})();
