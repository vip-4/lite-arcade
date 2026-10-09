/* 记忆翻牌 Memory — 原生 Canvas 实现，零依赖 */
(function () {
  'use strict';
  var canvas = document.getElementById('game-canvas');
  if (!canvas) return;

  var SIZE = 480, N = 4, PAD = 14, GAP = 10;
  var CELL = (SIZE - PAD * 2 - GAP * (N - 1)) / N;
  var ICONS = ['🍎', '🍇', '🍋', '🥑', '🍒', '🥕', '🌽', '🍄'];

  var movesEl = document.querySelector('[data-hud="moves"]');
  var timeEl = document.querySelector('[data-hud="time"]');

  Arcade.create({
    canvas: canvas,
    width: SIZE,
    height: SIZE,
    storageKey: 'lite-arcade:memory',
    tick: 0,

    reset: function () {
      var deck = ICONS.concat(ICONS).map(function (ic, i) {
        return { id: i, icon: ic, flipped: false, matched: false };
      });
      for (var i = deck.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1));
        var t = deck[i]; deck[i] = deck[j]; deck[j] = t;
      }
      return { cards: deck, first: null, lock: false, moves: 0, matched: 0, ms: 0 };
    },

    onTap: function (g, x, y) {
      var s = g.state;
      if (!s || s.lock || g.over) return;
      var col = Math.floor((x - PAD) / (CELL + GAP));
      var row = Math.floor((y - PAD) / (CELL + GAP));
      if (col < 0 || row < 0 || col >= N || row >= N) return;
      var idx = row * N + col;
      var card = s.cards[idx];
      if (!card || card.flipped || card.matched) return;

      card.flipped = true;
      if (s.first === null) { s.first = idx; return; }

      var a = s.cards[s.first], b = card;
      s.moves++;
      if (movesEl) movesEl.textContent = String(s.moves);

      if (a.icon === b.icon) {
        a.matched = b.matched = true;
        s.first = null;
        s.matched++;
        g.addScore(10);
        if (s.matched === ICONS.length) {
          var sec = (s.ms / 1000).toFixed(1);
          g.gameOver('全部配对完成！共 ' + s.moves + ' 步，用时 ' + sec + ' 秒。');
        }
      } else {
        s.lock = true;
        setTimeout(function () {
          a.flipped = false; b.flipped = false;
          s.lock = false;
          s.first = null;
        }, 700);
      }
    },

    update: function (g, dt) {
      var s = g.state;
      if (!s || g.over || !g.running) return;
      s.ms += dt;
      if (timeEl) timeEl.textContent = (s.ms / 1000).toFixed(1);
    },

    draw: function (g, ctx) {
      ctx.fillStyle = '#05070f';
      ctx.fillRect(0, 0, SIZE, SIZE);
      var s = g.state;
      if (!s) return;

      for (var i = 0; i < s.cards.length; i++) {
        var c = s.cards[i];
        var col = i % N, row = Math.floor(i / N);
        var x = PAD + col * (CELL + GAP), y = PAD + row * (CELL + GAP);

        if (c.matched) {
          ctx.fillStyle = 'rgba(74,222,128,.14)';
          Arcade.roundRect(ctx, x, y, CELL, CELL, 10); ctx.fill();
          ctx.strokeStyle = 'rgba(74,222,128,.5)'; ctx.lineWidth = 2; ctx.stroke();
          Arcade.centerText(ctx, c.icon, x + CELL / 2, y + CELL / 2, 40, 'rgba(255,255,255,.35)', 700);
        } else if (c.flipped) {
          var grd = ctx.createLinearGradient(x, y, x + CELL, y + CELL);
          grd.addColorStop(0, '#16203c'); grd.addColorStop(1, '#22304f');
          ctx.fillStyle = grd;
          Arcade.roundRect(ctx, x, y, CELL, CELL, 10); ctx.fill();
          Arcade.centerText(ctx, c.icon, x + CELL / 2, y + CELL / 2, 42, '#fff', 700);
        } else {
          ctx.fillStyle = '#141c33';
          Arcade.roundRect(ctx, x, y, CELL, CELL, 10); ctx.fill();
          ctx.strokeStyle = 'rgba(110,231,255,.28)'; ctx.lineWidth = 2; ctx.stroke();
          Arcade.centerText(ctx, '?', x + CELL / 2, y + CELL / 2, 30, 'rgba(110,231,255,.8)', 800);
        }
      }
    }
  });
})();
