/* 像素飞鸟 Flappy — 原生 Canvas 实现，零依赖 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  var W = 480, H = 640;
  var GRAVITY = 0.42, FLAP = -7.2, PIPE_W = 68, GAP = 168, SPEED = 2.4, INTERVAL = 1500;

  Arcade.create({
    canvas: canvas,
    width: W,
    height: H,
    storageKey: 'lite-arcade:bird',
    tick: 16,

    reset: function () {
      return {
        bird: { x: 120, y: H / 2, vy: 0, r: 13, rot: 0 },
        pipes: [],
        spawnAt: 900,
        elapsed: 0,
        passed: []
      };
    },

    onTap: function (g) { flap(g); },
    onSwipe: function (g, dir) { if (dir === 'up') flap(g); },
    onKey: function (g, key) { if (key === 'up' || key === ' ' || key === 'Enter') flap(g); },

    update: function (g, dt) {
      var s = g.state, b = s.bird;
      s.elapsed += dt;

      b.vy += GRAVITY;
      b.vy = Math.min(b.vy, 11);
      b.y += b.vy;
      b.rot = Arcade.clamp(b.vy / 11, -0.5, 1) * 0.7;

      if (b.y + b.r > H - 40) { g.gameOver('小鸟落地了。'); return; }
      if (b.y - b.r < 0) { b.y = b.r; b.vy = 0; }

      // 生成管道
      if (s.elapsed > s.spawnAt) {
        s.spawnAt = s.elapsed + INTERVAL;
        var top = Arcade.randInt(70, H - 40 - GAP - 70);
        s.pipes.push({ x: W + 10, top: top, h: GAP, scored: false });
      }

      for (var i = s.pipes.length - 1; i >= 0; i--) {
        var p = s.pipes[i];
        p.x -= SPEED;

        var hitX = b.x + b.r > p.x - PIPE_W / 2 && b.x - b.r < p.x + PIPE_W / 2;
        if (hitX && (b.y - b.r < p.top || b.y + b.r > p.top + p.h)) {
          g.gameOver('撞到管道了。');
          return;
        }
        if (!p.scored && p.x + PIPE_W / 2 < b.x) { p.scored = true; g.addScore(1); }
        if (p.x + PIPE_W < -20) s.pipes.splice(i, 1);
      }
    },

    draw: function (g, ctx) {
      // 天空渐变
      var sky = ctx.createLinearGradient(0, 0, 0, H);
      sky.addColorStop(0, '#0a1430');
      sky.addColorStop(.6, '#0d1c3c');
      sky.addColorStop(1, '#132a4d');
      ctx.fillStyle = sky;
      ctx.fillRect(0, 0, W, H);

      var s = g.state;
      if (!s) return;

      // 远景装饰
      ctx.fillStyle = 'rgba(110,231,255,.10)';
      for (var c = 0; c < 6; c++) {
        var cx = ((c * 97 + (s.elapsed * 0.02)) % (W + 120)) - 60;
        ctx.beginPath();
        ctx.arc(cx, 90 + (c % 3) * 46, 26 + (c % 2) * 10, 0, Arcade.TAU);
        ctx.fill();
      }

      // 管道
      for (var i = 0; i < s.pipes.length; i++) {
        var p = s.pipes[i];
        drawPipe(ctx, p.x - PIPE_W / 2, 0, PIPE_W, p.top);
        drawPipe(ctx, p.x - PIPE_W / 2, p.top + p.h, PIPE_W, H - 40 - (p.top + p.h));
      }

      // 地面
      ctx.fillStyle = '#0a1226';
      ctx.fillRect(0, H - 40, W, 40);
      ctx.fillStyle = 'rgba(110,231,255,.25)';
      ctx.fillRect(0, H - 40, W, 3);

      // 小鸟
      var b = s.bird;
      ctx.save();
      ctx.translate(b.x, b.y);
      ctx.rotate(b.rot);
      ctx.fillStyle = '#ffd166';
      Arcade.roundRect(ctx, -b.r, -b.r, b.r * 2, b.r * 2, 6);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.beginPath();
      ctx.arc(4, -3, 3.2, 0, Arcade.TAU);
      ctx.fill();
      ctx.fillStyle = '#1b1b1b';
      ctx.beginPath();
      ctx.arc(5.2, -3, 1.5, 0, Arcade.TAU);
      ctx.fill();
      ctx.fillStyle = '#ff9f43';
      ctx.beginPath();
      ctx.moveTo(b.r - 2, 0); ctx.lineTo(b.r + 9, 3); ctx.lineTo(b.r - 2, 7);
      ctx.closePath(); ctx.fill();
      ctx.restore();
    }
  });

  function flap(g) {
    if (!g.state || g.over) return;
    g.state.bird.vy = FLAP;
  }

  function drawPipe(ctx, x, y, w, h) {
    if (h <= 0) return;
    var grd = ctx.createLinearGradient(x, 0, x + w, 0);
    grd.addColorStop(0, '#2f7d5f');
    grd.addColorStop(.5, '#4ade80');
    grd.addColorStop(1, '#2f7d5f');
    ctx.fillStyle = grd;
    ctx.fillRect(x, y, w, h);
    ctx.fillStyle = 'rgba(255,255,255,.18)';
    ctx.fillRect(x + 4, y, 6, h);
    ctx.strokeStyle = 'rgba(0,0,0,.35)';
    ctx.lineWidth = 2;
    ctx.strokeRect(x + 1, y + 1, w - 2, h - 2);
  }
})();
