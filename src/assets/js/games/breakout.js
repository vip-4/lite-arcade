/* 打砖块 Breakout — 原生 Canvas 实现，零依赖 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  var W = 480, H = 560;
  var BCOLS = 8, BROWS = 5;
  var BW = (W - 24 - (BCOLS - 1) * 6) / BCOLS, BH = 20;
  var PALETTE = ['#6ee7ff', '#a78bfa', '#ffd166', '#4ade80', '#ff6b81'];

  Arcade.create({
    canvas: canvas,
    width: W,
    height: H,
    storageKey: 'lite-arcade:breakout',
    tick: 16,

    reset: function () {
      var bricks = [], r, c;
      for (r = 0; r < BROWS; r++) for (c = 0; c < BCOLS; c++) {
        bricks.push({ x: 12 + c * (BW + 6), y: 48 + r * (BH + 6), w: BW, h: BH, alive: true, row: r });
      }
      return {
        bricks: bricks,
        paddle: { x: W / 2 - 45, y: H - 32, w: 90, h: 12 },
        ball: { x: W / 2, y: H - 60, vx: 2.6, vy: -3.2, r: 7 },
        lives: 3,
        speed: 1
      };
    },

    onDrag: function (g, x) {
      var s = g.state;
      if (!s) return;
      s.paddle.x = Arcade.clamp(x - s.paddle.w / 2, 0, W - s.paddle.w);
    },

    onTap: function (g, x) {
      var s = g.state;
      if (!s) return;
      s.paddle.x = Arcade.clamp(x - s.paddle.w / 2, 0, W - s.paddle.w);
    },

    onKey: function (g, key) {
      var s = g.state;
      if (!s) return;
      var step = 34;
      if (key === 'left') s.paddle.x = Arcade.clamp(s.paddle.x - step, 0, W - s.paddle.w);
      else if (key === 'right') s.paddle.x = Arcade.clamp(s.paddle.x + step, 0, W - s.paddle.w);
    },

    update: function (g) {
      var s = g.state, b = s.ball, p = s.paddle;
      b.x += b.vx * s.speed;
      b.y += b.vy * s.speed;

      if (b.x - b.r < 0) { b.x = b.r; b.vx = Math.abs(b.vx); }
      if (b.x + b.r > W) { b.x = W - b.r; b.vx = -Math.abs(b.vx); }
      if (b.y - b.r < 0) { b.y = b.r; b.vy = Math.abs(b.vy); }

      // 挡板反弹：按命中位置改变水平速度，增加操控感
      if (b.vy > 0 && b.y + b.r >= p.y && b.y - b.r <= p.y + p.h &&
        b.x >= p.x - b.r && b.x <= p.x + p.w + b.r) {
        b.y = p.y - b.r;
        var hit = (b.x - (p.x + p.w / 2)) / (p.w / 2);
        b.vx = Arcade.clamp(hit * 4.2, -4.6, 4.6);
        b.vy = -Math.abs(b.vy);
        s.speed = Math.min(1.9, s.speed + 0.03);
      }

      // 砖块碰撞
      for (var i = 0; i < s.bricks.length; i++) {
        var k = s.bricks[i];
        if (!k.alive) continue;
        if (b.x + b.r > k.x && b.x - b.r < k.x + k.w && b.y + b.r > k.y && b.y - b.r < k.y + k.h) {
          k.alive = false;
          b.vy = -b.vy;
          g.addScore(10 + k.row * 5);
          break;
        }
      }

      var remain = s.bricks.filter(function (k) { return k.alive; }).length;
      if (remain === 0) {
        g.addScore(s.lives * 50);
        g.gameOver('全部砖块已清除，通关！');
        return;
      }

      if (b.y - b.r > H) {
        s.lives--;
        if (s.lives <= 0) { g.gameOver('三次漏球，游戏结束。'); return; }
        b.x = p.x + p.w / 2;
        b.y = p.y - 12;
        b.vx = 2.6; b.vy = -3.2;
        s.speed = 1;
        g.paused = true;
        g.showOverlay('还剩 ' + s.lives + ' 次机会', '按空格或点击“继续”继续游戏。');
      }
    },

    draw: function (g, ctx) {
      ctx.fillStyle = '#05070f';
      ctx.fillRect(0, 0, W, H);
      var s = g.state;
      if (!s) return;

      for (var i = 0; i < s.bricks.length; i++) {
        var k = s.bricks[i];
        if (!k.alive) continue;
        ctx.fillStyle = PALETTE[k.row % PALETTE.length];
        Arcade.roundRect(ctx, k.x, k.y, k.w, k.h, 4);
        ctx.fill();
      }

      var p = s.paddle, b = s.ball;
      var grad = ctx.createLinearGradient(p.x, 0, p.x + p.w, 0);
      grad.addColorStop(0, '#6ee7ff');
      grad.addColorStop(1, '#a78bfa');
      ctx.fillStyle = grad;
      Arcade.roundRect(ctx, p.x, p.y, p.w, p.h, 6);
      ctx.fill();

      ctx.fillStyle = '#ffd166';
      ctx.beginPath();
      ctx.arc(b.x, b.y, b.r, 0, Arcade.TAU);
      ctx.fill();

      ctx.fillStyle = 'rgba(255,255,255,.55)';
      ctx.font = '600 13px -apple-system, "PingFang SC", sans-serif';
      ctx.textAlign = 'left';
      ctx.fillText('♥'.repeat(Math.max(0, s.lives)), 12, 28);
      ctx.textAlign = 'right';
      ctx.fillText('剩余砖块 ' + s.bricks.filter(function (k) { return k.alive; }).length, W - 12, 28);
    }
  });
})();
