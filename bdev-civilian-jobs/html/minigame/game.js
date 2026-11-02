(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    const $ = (id) => document.getElementById(id);
    const el = (tag, cls, html) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (html != null) e.innerHTML = html;
        return e;
    };
    const lerp = (a, b, t) => a + (b - a) * t;
    const rand = (a, b) => a + Math.random() * (b - a);
    const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    function post(name, data) {
        if (!RESOURCE) { console.log('[minigame]', name, data); return; }
        fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        }).catch(() => {});
    }

    // ------------------------------------------------------------------
    // Runner: one game at a time. Each game gets an `api` object.
    // ------------------------------------------------------------------
    const Games = {};
    let active = null;

    function start(msg) {
        if (active) end({ success: false, cancelled: true }, true);
        const make = Games[msg.game];
        if (!make) {
            post('minigame:done', { id: msg.id, success: false, cancelled: true, error: 'unknown game ' + msg.game });
            return;
        }
        const o = Object.assign({ difficulty: 0.5 }, msg.opts || {});
        const state = {
            id: msg.id, mistakes: 0, allowed: o.misses ?? 3, loops: [], keys: {}, raf: 0, last: 0,
            timeLeft: o.time || 0, done: false,
        };
        active = state;

        $('mg-title').textContent = o.title || 'Minigame';
        $('mg-hint').textContent = o.hint || '';
        $('mg-keys').innerHTML = '';
        const stage = $('mg-stage');
        stage.innerHTML = '';
        renderMistakes();
        $('mg-timer').classList.toggle('hidden', !state.timeLeft);
        $('mg').classList.remove('hidden');

        const api = {
            o, stage,
            hint: (t) => { $('mg-hint').textContent = t; },
            keys: (html) => { $('mg-keys').innerHTML = html; },
            loop: (fn) => state.loops.push(fn),
            on: (name, fn) => { state.keys[name] = fn; },
            finish: (res) => end(res),
            mistake: () => {
                state.mistakes++;
                renderMistakes();
                const p = document.querySelector('.panel');
                p.classList.remove('shake'); void p.offsetWidth; p.classList.add('shake');
                if (state.mistakes > state.allowed) {
                    end({ success: false, quality: 0 });
                    return true;
                }
                return false;
            },
            get mistakes() { return state.mistakes; },
        };

        make(o, api);

        state.last = performance.now();
        const tick = (now) => {
            if (active !== state) return;
            const dt = Math.min(0.05, (now - state.last) / 1000);
            state.last = now;
            if (state.timeLeft) {
                state.timeLeft = Math.max(0, state.timeLeft - dt);
                const t = $('mg-timer');
                t.textContent = state.timeLeft.toFixed(1) + 's';
                t.classList.toggle('low', state.timeLeft < 4);
                if (state.timeLeft <= 0) { end({ success: false, quality: 0, timeout: true }); return; }
            }
            for (const fn of state.loops) fn(dt);
            if (active === state) state.raf = requestAnimationFrame(tick);
        };
        state.raf = requestAnimationFrame(tick);
    }

    function renderMistakes() {
        const box = $('mg-mistakes');
        if (!active) return;
        box.innerHTML = active.allowed > 0 ? 'Mistakes ' : '';
        for (let i = 0; i < active.allowed; i++) {
            box.appendChild(el('span', 'x' + (i < active.mistakes ? ' on' : '')));
        }
    }

    function end(res, silent) {
        const state = active;
        if (!state || state.done) return;
        state.done = true;
        cancelAnimationFrame(state.raf);
        active = null;
        $('mg').classList.add('hidden');
        $('mg-stage').innerHTML = '';
        const out = Object.assign({ success: false, quality: 0 }, res, { id: state.id, mistakes: state.mistakes });
        out.quality = clamp(Number(out.quality) || 0, 0, 1);
        if (!silent) post('minigame:done', out);
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'start') start(d);
        else if (d.action === 'stop' && active) end({ success: false, cancelled: true }, true);
    });

    // keyboard + mouse routing: "press" = space / left mouse, "release" on up
    let holding = false;
    function press() { if (active && !holding) { holding = true; active.keys.press && active.keys.press(); } }
    function release() { if (active && holding) { holding = false; active.keys.release && active.keys.release(); } }
    window.addEventListener('keydown', (e) => {
        if (!active) return;
        if (e.key === 'Escape') { end({ success: false, cancelled: true }); return; }
        if (e.code === 'Space') { e.preventDefault(); press(); }
        if (e.key === 'Enter' && active.keys.enter) active.keys.enter();
    });
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') release(); });
    document.addEventListener('mousedown', (e) => {
        if (e.button === 0 && e.target.closest && e.target.closest('.hold-area')) press();
    });
    document.addEventListener('mouseup', (e) => { if (e.button === 0) release(); });

    // ------------------------------------------------------------------
    // pump: hit SPACE while the needle is in the green zone
    //   opts: hits (5), misses (3)
    // ------------------------------------------------------------------
    Games.pump = (o, api) => {
        const need = o.hits || 5;
        const zoneW = lerp(0.30, 0.11, o.difficulty);
        const speed = lerp(0.75, 1.75, o.difficulty);
        api.hint(o.hint || 'Press SPACE when the needle is in the green.');
        api.keys('<kbd>SPACE</kbd> pump &nbsp; <kbd>ESC</kbd> stop');

        const bar = el('div', 'bar hold-area');
        const zone = el('div', 'zone');
        const needle = el('div', 'needle');
        bar.append(zone, needle);
        const pips = el('div', 'pips');
        for (let i = 0; i < need; i++) pips.appendChild(el('div', 'pip'));
        api.stage.append(bar, pips);

        let pos = 0, dir = 1, z = 0, got = 0;
        const placeZone = () => {
            z = rand(0.08, 0.92 - zoneW);
            zone.style.left = (z * 100) + '%';
            zone.style.width = (zoneW * 100) + '%';
        };
        placeZone();

        api.loop((dt) => {
            pos += dir * speed * dt;
            if (pos >= 1) { pos = 1; dir = -1; }
            if (pos <= 0) { pos = 0; dir = 1; }
            needle.style.left = (pos * 100) + '%';
        });
        api.on('press', () => {
            if (pos >= z && pos <= z + zoneW) {
                pips.children[got].classList.add('on');
                got++;
                bar.classList.remove('flash-good'); void bar.offsetWidth; bar.classList.add('flash-good');
                if (got >= need) return api.finish({ success: true, quality: need / (need + api.mistakes) });
                placeZone();
            } else {
                bar.classList.remove('flash-bad'); void bar.offsetWidth; bar.classList.add('flash-bad');
                api.mistake();
            }
        });
    };

    // ------------------------------------------------------------------
    // nuts: click the lug nuts in a star (criss-cross) pattern
    //   opts: count (5), action ('Loosen' | 'Tighten')
    // ------------------------------------------------------------------
    function starOrder(n) {
        const order = [];
        if (n % 2 === 1) {
            for (let i = 0; i < n; i++) order.push((i * 2) % n);
        } else {
            for (let i = 0; i < n / 2; i++) order.push(i, i + n / 2);
        }
        return order;
    }

    Games.nuts = (o, api) => {
        const n = clamp(o.count || 5, 4, 8);
        const start = Math.floor(Math.random() * n);
        const order = starOrder(n).map((i) => (i + start) % n);
        const showHints = o.difficulty < 0.55;
        api.hint(o.hint || `${o.action || 'Loosen'} the nuts in a star pattern: always jump across the wheel, never to the nut next door.`);
        api.keys('<kbd>CLICK</kbd> nut &nbsp; <kbd>ESC</kbd> stop');

        const wheel = el('div', 'wheel');
        wheel.appendChild(el('div', 'hub'));
        const nuts = [];
        for (let i = 0; i < n; i++) {
            const a = (i / n) * Math.PI * 2 - Math.PI / 2;
            const b = el('div', 'nut');
            b.style.left = (105 + Math.cos(a) * 66) + 'px';
            b.style.top = (105 + Math.sin(a) * 66) + 'px';
            b.addEventListener('click', () => pick(i));
            wheel.appendChild(b);
            nuts.push(b);
        }
        api.stage.appendChild(wheel);

        let step = 0;
        const mark = () => {
            nuts.forEach((b) => b.classList.remove('next'));
            if (step < n && (showHints || step === 0)) nuts[order[step]].classList.add('next');
        };
        mark();

        function pick(i) {
            if (nuts[i].classList.contains('done')) return;
            if (i === order[step]) {
                nuts[i].classList.add('done');
                nuts[i].textContent = String(step + 1);
                step++;
                if (step >= n) return api.finish({ success: true, quality: n / (n + api.mistakes * 1.5) });
                mark();
            } else {
                nuts[i].classList.add('wrong');
                setTimeout(() => nuts[i].classList.remove('wrong'), 300);
                api.mistake();
            }
        }
    };

    // ------------------------------------------------------------------
    // torque: hold to build torque, release inside the green band
    //   opts: count (4)
    // ------------------------------------------------------------------
    Games.torque = (o, api) => {
        const n = o.count || 4;
        const bandW = lerp(0.13, 0.05, o.difficulty);
        const rate = lerp(0.45, 0.8, o.difficulty);
        api.hint(o.hint || 'Hold SPACE to build torque and let go inside the green band. Too far strips the bolt.');
        api.keys('<kbd>HOLD SPACE</kbd> torque &nbsp; <kbd>ESC</kbd> stop');

        const wrap = el('div', 'gauge-wrap');
        const gauge = el('div', 'gauge');
        const lbl = el('div', 'label-row', '<span>0 Nm</span><span class="tq-bolt"></span><span>MAX</span>');
        const bar = el('div', 'bar hold-area');
        const band = el('div', 'zone');
        const fill = el('div', 'fill');
        bar.append(fill, band);
        gauge.append(lbl, bar);
        wrap.appendChild(gauge);
        const pips = el('div', 'pips');
        for (let i = 0; i < n; i++) pips.appendChild(el('div', 'pip'));
        api.stage.append(wrap, pips);

        let bolt = 0, level = 0, holding = false, target = 0, good = 0;
        const next = () => {
            target = rand(0.5, 0.85);
            band.style.left = ((target - bandW / 2) * 100) + '%';
            band.style.width = (bandW * 100) + '%';
            level = 0;
            lbl.querySelector('.tq-bolt').textContent = `Bolt ${bolt + 1} / ${n}`;
        };
        next();

        api.loop((dt) => {
            if (holding) {
                level += rate * dt * (0.55 + level);
                if (level >= 1) { level = 1; holding = false; strip(); }
            }
            fill.style.width = (level * 100) + '%';
            fill.classList.toggle('over', level > target + bandW / 2);
        });
        function strip() {
            bar.classList.remove('flash-bad'); void bar.offsetWidth; bar.classList.add('flash-bad');
            if (!api.mistake()) next();
        }
        api.on('press', () => { holding = true; });
        api.on('release', () => {
            if (!holding) return;
            holding = false;
            const d = Math.abs(level - target);
            if (d <= bandW / 2) {
                good += 1 - d / (bandW / 2) * 0.3;
                pips.children[bolt].classList.add('on');
                bolt++;
                if (bolt >= n) return api.finish({ success: true, quality: good / (n + api.mistakes) });
                next();
            } else {
                strip();
            }
        });
    };

    // ------------------------------------------------------------------
    // wiring
    //   mode 'match'    connect each wire to the plug of the same color (any order)
    //                   opts: count (4)
    //   mode 'sequence' connect clamps to terminals in a set order
    //                   opts: clamps [{id,label,color}], terminals [{id,label}], order [[clampId, terminalId], ...]
    // ------------------------------------------------------------------
    const COLORS = [
        ['#e74c3c', 'Red'], ['#3498db', 'Blue'], ['#f1c40f', 'Yellow'], ['#2ecc71', 'Green'],
        ['#ecf0f1', 'White'], ['#9b59b6', 'Purple'], ['#e67e22', 'Orange'], ['#1abc9c', 'Teal'],
    ];

    Games.wiring = (o, api) => {
        const seq = o.mode === 'sequence';
        api.keys('<kbd>CLICK</kbd> left, then right &nbsp; <kbd>ESC</kbd> stop');
        const wrap = el('div', 'wires');
        const left = el('div', 'col');
        const right = el('div', 'col');
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('class', 'lines');
        wrap.append(svg, left, right);
        api.stage.appendChild(wrap);
        const checklist = el('div', 'checklist');

        let selected = null;
        const node = (label, color, side) => {
            const n = el('div', 'node' + (side === 'right' ? ' right' : ''));
            const dot = `<span class="dot" style="background:${color || '#555'}"></span>`;
            n.innerHTML = side === 'right' ? `${esc(label)} ${dot}` : `${dot} ${esc(label)}`;
            return n;
        };
        const center = (n, side) => {
            const r = n.getBoundingClientRect();
            const w = wrap.getBoundingClientRect();
            return { x: (side === 'left' ? r.right : r.left) - w.left, y: r.top + r.height / 2 - w.top };
        };
        const draw = (a, b, color) => {
            const p1 = center(a, 'left'), p2 = center(b, 'right');
            const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
            line.setAttribute('x1', p1.x); line.setAttribute('y1', p1.y);
            line.setAttribute('x2', p2.x); line.setAttribute('y2', p2.y);
            line.setAttribute('stroke', color);
            svg.appendChild(line);
        };
        const spark = (n) => {
            const p = center(n, 'right');
            const s = el('div', 'spark');
            s.style.left = p.x + 'px'; s.style.top = p.y + 'px';
            wrap.appendChild(s);
            setTimeout(() => s.remove(), 400);
        };
        const select = (n, data) => {
            if (n.classList.contains('used')) return;
            left.querySelectorAll('.node').forEach((x) => x.classList.remove('sel'));
            n.classList.add('sel');
            selected = { n, data };
        };

        if (!seq) {
            const count = clamp(o.count || 4, 3, 8);
            api.hint(o.hint || 'Reconnect every wire to the plug with the same color.');
            const picks = COLORS.slice().sort(() => Math.random() - 0.5).slice(0, count);
            let done = 0;
            picks.forEach((c) => {
                const n = node(c[1], c[0], 'left');
                n.addEventListener('click', () => select(n, c));
                left.appendChild(n);
            });
            picks.slice().sort(() => Math.random() - 0.5).forEach((c) => {
                const n = node(o.difficulty > 0.6 ? 'Plug' : c[1], c[0], 'right');
                n.addEventListener('click', () => {
                    if (!selected || n.classList.contains('used')) return;
                    if (selected.data === c) {
                        draw(selected.n, n, c[0]);
                        selected.n.classList.add('used'); selected.n.classList.remove('sel'); n.classList.add('used');
                        selected = null;
                        done++;
                        if (done >= count) setTimeout(() => api.finish({ success: true, quality: count / (count + api.mistakes) }), 250);
                    } else {
                        spark(n);
                        api.mistake();
                    }
                });
                right.appendChild(n);
            });
            return;
        }

        // sequence mode
        const clamps = o.clamps || [];
        const terms = o.terminals || [];
        const order = o.order || [];
        const byId = (list, id) => list.find((x) => x.id === id) || { id, label: id };
        api.hint(o.hint || 'Connect them in the right order.');
        const leftNodes = {};
        clamps.forEach((c) => {
            const n = node(c.label, c.color, 'left');
            n.addEventListener('click', () => { if (step < order.length) select(n, c); });
            left.appendChild(n);
            leftNodes[c.id] = n;
        });
        let step = 0;
        const items = order.map(([cid, tid]) => {
            const li = el('div', '', `${esc(byId(clamps, cid).label)} → ${esc(byId(terms, tid).label)}`);
            checklist.appendChild(li);
            return li;
        });
        const showList = () => items.forEach((li, i) => {
            li.className = i < step ? 'done' : (i === step ? 'now' : '');
            // on hard difficulty the order is not shown, you have to know it
            li.style.display = (o.difficulty > 0.7 && i > step) ? 'none' : '';
        });
        showList();
        terms.forEach((t) => {
            const n = node(t.label, t.color, 'right');
            n.addEventListener('click', () => {
                if (!selected || n.classList.contains('used')) return;
                const [cid, tid] = order[step];
                if (selected.data.id === cid && t.id === tid) {
                    draw(selected.n, n, selected.data.color || '#ccc');
                    n.classList.add('used');
                    selected.n.classList.remove('sel');
                    selected = null;
                    step++;
                    showList();
                    if (step >= order.length) setTimeout(() => api.finish({ success: true, quality: order.length / (order.length + api.mistakes) }), 250);
                } else {
                    spark(n);
                    api.mistake();
                    active && (active.shock = true);
                }
            });
            right.appendChild(n);
        });
        api.stage.appendChild(checklist);
        // remember shocks so the job can react (ragdoll, damage)
        const origFinish = api.finish;
        api.finish = (res) => origFinish(Object.assign({ shock: api.mistakes > 0 }, res));
    };

    // ------------------------------------------------------------------
    // pour: hold to pour, stop inside the green band, ENTER when done
    //   opts: color ('#f5a524'), label ('Fuel')
    // ------------------------------------------------------------------
    Games.pour = (o, api) => {
        const bandW = lerp(0.14, 0.06, o.difficulty);
        const top = rand(0.86, 0.95);
        const lo = top - bandW;
        const color = o.color || '#f5a524';
        api.hint(o.hint || `Hold SPACE to pour. Stop in the green band, then press ENTER. Don't overfill.`);
        api.keys('<kbd>HOLD SPACE</kbd> pour &nbsp; <kbd>ENTER</kbd> done &nbsp; <kbd>ESC</kbd> stop');

        const wrap = el('div', 'pour');
        const tank = el('div', 'tank hold-area');
        const liquid = el('div', 'liquid');
        liquid.style.background = `linear-gradient(180deg, ${color}, ${color}aa)`;
        const band = el('div', 'zone');
        band.style.bottom = (lo * 100) + '%';
        band.style.height = (bandW * 100) + '%';
        tank.append(liquid, band);
        const side = el('div', 'pour-side');
        side.innerHTML = `<div>${esc(o.label || 'Level')}</div><div class="big" id="pour-pct">0%</div>`;
        const done = el('button', 'btn', 'Done (ENTER)');
        side.appendChild(done);
        wrap.append(tank, side);
        api.stage.appendChild(wrap);

        let level = 0, holding = false, t = 0, spills = 0;
        api.loop((dt) => {
            t += dt;
            if (holding) {
                // it glugs: uneven flow that speeds up as it fills
                const glug = 0.6 + 0.4 * Math.sin(t * lerp(7, 13, o.difficulty));
                level += dt * lerp(0.32, 0.5, o.difficulty) * glug * (0.6 + level);
                if (level > 1) {
                    level = top - bandW * 1.5;
                    holding = false;
                    spills++;
                    tank.classList.remove('flash-bad'); void tank.offsetWidth; tank.classList.add('flash-bad');
                    api.mistake();
                }
            }
            liquid.style.height = (Math.min(1, level) * 100) + '%';
            const pct = $('pour-pct');
            if (pct) pct.textContent = Math.round(level * 100) + '%';
        });
        api.on('press', () => { holding = true; });
        api.on('release', () => { holding = false; });
        const finish = () => {
            if (level < lo) {
                api.hint('Not full yet. Keep pouring.');
                tank.classList.remove('flash-bad'); void tank.offsetWidth; tank.classList.add('flash-bad');
                return;
            }
            const inBand = level <= top;
            api.finish({ success: true, quality: (inBand ? 1 : 0.6) / (1 + spills * 0.5) });
        };
        api.on('enter', finish);
        done.addEventListener('click', finish);
    };

    // ------------------------------------------------------------------
    // tension: hold to reel in; keep the tension in the green until the bar fills.
    // Hitting the red snaps the cable (fail).
    //   opts: duration (6 seconds of good tension)
    // ------------------------------------------------------------------
    Games.tension = (o, api) => {
        const need = o.duration || 6;
        const bandLo = lerp(0.35, 0.45, o.difficulty);
        const bandHi = bandLo + lerp(0.32, 0.18, o.difficulty);
        api.hint(o.hint || 'Hold SPACE to winch. Keep the tension in the green until the bar fills. Red snaps the cable.');
        api.keys('<kbd>HOLD SPACE</kbd> winch &nbsp; <kbd>ESC</kbd> stop');

        const lbl = el('div', 'label-row', '<span>Slack</span><span>Tension</span><span>Snap</span>');
        const bar = el('div', 'bar hold-area');
        const band = el('div', 'zone');
        band.style.left = (bandLo * 100) + '%';
        band.style.width = ((bandHi - bandLo) * 100) + '%';
        const red = el('div', 'zone red');
        red.style.left = '90%'; red.style.width = '10%';
        const needle = el('div', 'needle');
        bar.append(band, red, needle);
        const prog = el('div', 'progress');
        const progFill = el('div');
        prog.appendChild(progFill);
        api.stage.append(lbl, bar, prog);

        let t = 0.2, held = false, good = 0, total = 0, gust = 0, gustT = 0;
        api.loop((dt) => {
            gustT -= dt;
            if (gustT <= 0) { gust = rand(-0.25, 0.35) * lerp(0.6, 1.4, o.difficulty); gustT = rand(0.6, 1.6); }
            t += (held ? 0.42 : -0.38) * dt + gust * dt;
            t = clamp(t, 0, 1);
            needle.style.left = (t * 100) + '%';
            total += dt;
            if (t >= bandLo && t <= bandHi) good += dt;
            progFill.style.width = Math.min(100, good / need * 100) + '%';
            if (t >= 0.9) return api.finish({ success: false, quality: 0, snapped: true });
            if (good >= need) api.finish({ success: true, quality: clamp(need / total * 1.25, 0.3, 1) });
        });
        api.on('press', () => { held = true; });
        api.on('release', () => { held = false; });
    };

    // Open the page in a normal browser to try the games: ?game=nuts
    if (!RESOURCE) {
        const g = new URLSearchParams(location.search).get('game') || 'pump';
        const demo = {
            wiring: {
                mode: 'sequence', title: 'Jump start',
                clamps: [{ id: 'red', label: 'Red clamp', color: '#e74c3c' }, { id: 'black', label: 'Black clamp', color: '#222' }],
                terminals: [{ id: 'dead_pos', label: 'Dead battery +' }, { id: 'good_pos', label: 'Truck battery +' }, { id: 'good_neg', label: 'Truck battery -' }, { id: 'ground', label: 'Engine block (ground)' }],
                order: [['red', 'dead_pos'], ['red', 'good_pos'], ['black', 'good_neg'], ['black', 'ground']],
            },
        };
        document.body.style.background = '#333';
        start({ id: 1, game: g, opts: Object.assign({ title: g, time: 0 }, demo[g] || {}) });
    }
})();
