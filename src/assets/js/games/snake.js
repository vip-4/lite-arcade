/* 贪吃蛇 Snake — 原生 Canvas 实现，零依赖 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  var CELL = 20, COLS = 24, ROWS = 24, W = COLS * CELL, H = ROWS * CELL;
  var OPP = { up: 'down', down: 'up', left: 'right', right: 'left' };

  function spawn(snake) {
    var free = [], occupied = {}, i;
    for (i = 0; i < snake.length; i++) occupied[snake[i].x + ',' + snake[i].y] = 1;
    for (var y = 0; y < ROWS; y++) for (var x = 0; x < COLS; x++) {
      if (!occupied[x + ',' + y]) free.push({ x: x, y: y });
    }
    return free.length ? free[Math.floor(Math.random() * free.length)] : null;
  }

  Arcade.create({
    canvas: canvas,
    width: W,
    height: H,
    storageKey: 'lite-arcade:snake',
    tick: 110,

    reset: function (g) {
      var s = {
        snake: [{ x: 12, y: 12 }, { x: 11, y: 12 }, { x: 10, y: 12 }],
        dir: 'right', pending: 'right', food: null
      };
      s.food = spawn(s.snake);
      return s;
    },

    onSwipe: function (g, dir) {
      var s = g.state;
      if (!s || OPP[s.dir] === dir) return;
      s.pending = dir;
    },

    update: function (g) {
      var s = g.state;
      s.dir = s.pending;
      var head = s.snake[0], nx = head.x, ny = head.y;
      if (s.dir === 'up') ny--; else if (s.dir === 'down') ny++;
      else if (s.dir === 'left') nx--; else nx++;

      if (nx < 0 || ny < 0 || nx >= COLS || ny >= ROWS) { g.gameOver('撞到边界了。'); return; }
      for (var i = 0; i < s.snake.length - 1; i++) {
        if (s.snake[i].x === nx && s.snake[i].y === ny) { g.gameOver('撞到自己了。'); return; }
      }

      s.snake.unshift({ x: nx, y: ny });
      if (s.food && nx === s.food.x && ny === s.food.y) {
        g.addScore(10);
        s.food = spawn(s.snake);
        if (!s.food) { g.gameOver('棋盘已被填满，通关！'); return; }
      } else {
        s.snake.pop();
      }
    },

    draw: function (g, ctx) {
      ctx.fillStyle = '#05070f';
      ctx.fillRect(0, 0, W, H);

      ctx.strokeStyle = 'rgba(110,231,255,.06)';
      ctx.lineWidth = 1;
      for (var x = 0; x <= COLS; x++) { ctx.beginPath(); ctx.moveTo(x * CELL, 0); ctx.lineTo(x * CELL, H); ctx.stroke(); }
      for (var y = 0; y <= ROWS; y++) { ctx.beginPath(); ctx.moveTo(0, y * CELL); ctx.lineTo(W, y * CELL); ctx.stroke(); }

      var s = g.state;
      if (!s) return;

      if (s.food) {
        ctx.fillStyle = '#ffd166';
        ctx.beginPath();
        ctx.arc(s.food.x * CELL + CELL / 2, s.food.y * CELL + CELL / 2, CELL * 0.34, 0, Arcade.TAU);
        ctx.fill();
      }

      for (var i = s.snake.length - 1; i >= 0; i--) {
        var seg = s.snake[i];
        var t = i / Math.max(1, s.snake.length - 1);
        ctx.fillStyle = i === 0 ? '#6ee7ff' : 'rgba(167,139,250,' + (0.95 - t * 0.5).toFixed(2) + ')';
        Arcade.roundRect(ctx, seg.x * CELL + 1.5, seg.y * CELL + 1.5, CELL - 3, CELL - 3, 5);
        ctx.fill();
      }
    }
  });
})();
