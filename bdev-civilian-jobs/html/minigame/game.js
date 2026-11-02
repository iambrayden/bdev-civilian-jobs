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
        if (active && active.keys.key) active.keys.key(e);
    });
    window.addEventListener('wheel', (e) => { if (active && active.keys.wheel) active.keys.wheel(e); }, { passive: true });
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

    // ------------------------------------------------------------------
    // pins: pin-tumbler lockpick. Pick a pin (←/→ or mouse), hold SPACE to lift it,
    // let go when it sits on the shear line. Only the binding pin sets; it lifts
    // stiffly (that's the feel to look for). Lifting the binding pin too far oversets it.
    //   opts: count (5)
    // ------------------------------------------------------------------
    Games.pins = (o, api) => {
        const n = clamp(o.count || 5, 3, 7);
        const band = lerp(0.1, 0.045, o.difficulty);
        const feel = o.difficulty < 0.6; // easy: the binding pin visibly shudders
        api.hint(o.hint || 'Pick a pin with ←/→ (or the mouse) and hold SPACE to lift it. The binding pin feels stiff. Let go when it reaches the shear line.');
        api.keys('<kbd>←</kbd><kbd>→</kbd> pin &nbsp; <kbd>HOLD SPACE</kbd> lift &nbsp; <kbd>ESC</kbd> stop');

        const wrap = el('div', 'pins');
        const shear = el('div', 'shear');
        wrap.appendChild(shear);
        const order = Array.from({ length: n }, (_, i) => i).sort(() => Math.random() - 0.5);
        const pins = [];
        for (let i = 0; i < n; i++) {
            const col = el('div', 'pin-col hold-area');
            const pin = el('div', 'pin');
            pin.innerHTML = '<div class="driver"></div><div class="key"></div>';
            col.appendChild(pin);
            col.addEventListener('mousedown', () => select(i));
            col.addEventListener('mouseenter', () => { if (!lifting) select(i); });
            wrap.appendChild(col);
            pins.push({ col, pin, need: rand(0.45, 0.8), h: 0, set: false });
        }
        api.stage.appendChild(wrap);

        let sel = 0, lifting = false, step = 0;
        const select = (i) => {
            if (lifting) return;
            sel = clamp(i, 0, n - 1);
            pins.forEach((p, k) => p.col.classList.toggle('sel', k === sel));
        };
        select(0);
        // the shear line sits at the binding pin's "need" height; each pin needs its own lift
        const draw = () => pins.forEach((p, k) => {
            const lift = p.set ? p.need : p.h;
            p.pin.style.transform = `translateY(${-lift * 70}px)`;
            p.col.classList.toggle('set', p.set);
            const binding = order[step] === k && !p.set;
            p.pin.classList.toggle('shudder', feel && lifting && sel === k && binding && p.h > 0.05);
        });
        shear.style.bottom = '0';

        api.loop((dt) => {
            const p = pins[sel];
            if (lifting && !p.set) {
                const binding = order[step] === sel;
                p.h = Math.min(1, p.h + dt * (binding ? 0.45 : 1.1));
                if (binding && p.h > p.need + band) {
                    // overset: the pin jams past the shear line
                    lifting = false;
                    p.h = 0;
                    p.col.classList.remove('flash-bad'); void p.col.offsetWidth; p.col.classList.add('flash-bad');
                    api.mistake();
                }
            } else if (!p.set) {
                p.h = Math.max(0, p.h - dt * 2.5);
            }
            pins.forEach((q, k) => { if (k !== sel && !q.set) q.h = Math.max(0, q.h - dt * 2.5); });
            // the shear line marker follows the selected pin's target so the player can read it
            shear.style.transform = `translateY(${-(pins[sel].need) * 70}px)`;
            draw();
        });
        api.on('key', (e) => {
            if (e.key === 'ArrowLeft' || e.key === 'a') select(sel - 1);
            if (e.key === 'ArrowRight' || e.key === 'd') select(sel + 1);
        });
        api.on('press', () => { if (!pins[sel].set) lifting = true; });
        api.on('release', () => {
            if (!lifting) return;
            lifting = false;
            const p = pins[sel];
            const binding = order[step] === sel;
            if (binding && Math.abs(p.h - p.need) <= band) {
                p.set = true;
                p.col.classList.remove('flash-good'); void p.col.offsetWidth; p.col.classList.add('flash-good');
                step++;
                if (step >= n) setTimeout(() => api.finish({ success: true, quality: n / (n + api.mistakes * 1.5) }), 250);
            }
        });
    };

    // ------------------------------------------------------------------
    // slimjim: click the gap in the window seal, then steer the rod (mouse) down
    // through the door to the lock rod and click to hook it. Touching anything snags.
    //   opts: obstacles (4)
    // ------------------------------------------------------------------
    Games.slimjim = (o, api) => {
        const W = 480, H = 220;
        const count = o.obstacles || Math.round(lerp(3, 6, o.difficulty));
        api.hint(o.hint || 'Click the gap in the window seal, then guide the rod to the lock linkage without touching anything. Click to hook it.');
        api.keys('<kbd>MOUSE</kbd> steer &nbsp; <kbd>CLICK</kbd> hook &nbsp; <kbd>ESC</kbd> stop');
        const cv = el('canvas', 'jim');
        cv.width = W; cv.height = H;
        api.stage.appendChild(cv);
        const ctx = cv.getContext('2d');
        const slot = { x: rand(60, 140), y: 14 };
        const target = { x: rand(330, 430), y: rand(150, 195), r: lerp(16, 10, o.difficulty) };
        const obs = [];
        for (let i = 0; i < count; i++) {
            const vertical = Math.random() < 0.4;
            const w = vertical ? 10 : rand(70, 150), h = vertical ? rand(50, 90) : 10;
            const ob = { x: rand(40, W - 40 - w), y: rand(40, H - 30 - h), w, h };
            if (Math.hypot(ob.x + w / 2 - target.x, ob.y + h / 2 - target.y) < 50) { i--; continue; }
            if (ob.y < 50 && Math.abs(ob.x + w / 2 - slot.x) < 60) { i--; continue; }
            obs.push(ob);
        }
        let inserted = false, tip = { x: slot.x, y: slot.y }, mouse = { x: slot.x, y: slot.y }, flash = 0;
        const toLocal = (e) => {
            const r = cv.getBoundingClientRect();
            return { x: (e.clientX - r.left) * (W / r.width), y: (e.clientY - r.top) * (H / r.height) };
        };
        cv.addEventListener('mousemove', (e) => { mouse = toLocal(e); });
        cv.addEventListener('click', (e) => {
            const m = toLocal(e);
            if (!inserted) {
                if (Math.hypot(m.x - slot.x, m.y - slot.y) < 18) { inserted = true; tip = { x: slot.x, y: slot.y + 6 }; }
                return;
            }
            if (Math.hypot(tip.x - target.x, tip.y - target.y) <= target.r) {
                api.finish({ success: true, quality: 1 / (1 + api.mistakes * 0.4) });
            }
        });
        const snag = () => {
            flash = 0.3;
            inserted = false;
            tip = { x: slot.x, y: slot.y };
            api.mistake();
        };
        api.loop((dt) => {
            if (inserted) {
                // the rod follows the mouse, a little slowly, so you can't flick past things
                const max = 260 * dt;
                const dx = mouse.x - tip.x, dy = mouse.y - tip.y, d = Math.hypot(dx, dy);
                if (d > 0.5) { const k = Math.min(1, max / d); tip.x += dx * k; tip.y += dy * k; }
                tip.x = clamp(tip.x, 4, W - 4); tip.y = clamp(tip.y, 4, H - 4);
                if (tip.y < 12 && Math.abs(tip.x - slot.x) > 14) snag();
                for (const b of obs) if (tip.x > b.x - 2 && tip.x < b.x + b.w + 2 && tip.y > b.y - 2 && tip.y < b.y + b.h + 2) { snag(); break; }
            }
            flash = Math.max(0, flash - dt);
            // draw
            ctx.clearRect(0, 0, W, H);
            ctx.fillStyle = '#141924'; ctx.fillRect(0, 0, W, H);
            ctx.fillStyle = flash > 0 ? 'rgba(234,57,67,.35)' : '#2a3448'; ctx.fillRect(0, 0, W, 10); // glass
            ctx.fillStyle = '#0b0e14'; ctx.fillRect(slot.x - 12, 0, 24, 12);
            ctx.strokeStyle = '#f5a524'; ctx.lineWidth = 2; ctx.strokeRect(slot.x - 12, 0, 24, 12);
            ctx.fillStyle = '#4b5568';
            for (const b of obs) { ctx.beginPath(); ctx.roundRect ? ctx.roundRect(b.x, b.y, b.w, b.h, 4) : ctx.rect(b.x, b.y, b.w, b.h); ctx.fill(); }
            ctx.beginPath(); ctx.arc(target.x, target.y, target.r, 0, Math.PI * 2);
            ctx.fillStyle = 'rgba(22,199,132,.22)'; ctx.fill(); ctx.strokeStyle = '#16c784'; ctx.stroke();
            ctx.fillStyle = '#8a93a6'; ctx.font = '11px sans-serif'; ctx.fillText('lock rod', target.x - 20, target.y + target.r + 13);
            if (inserted) {
                ctx.strokeStyle = '#d7dbe3'; ctx.lineWidth = 3;
                ctx.beginPath(); ctx.moveTo(slot.x, 0); ctx.lineTo(tip.x, tip.y); ctx.stroke();
                ctx.beginPath(); ctx.arc(tip.x, tip.y, 4, 0, Math.PI * 2); ctx.fillStyle = '#fff'; ctx.fill();
            } else {
                ctx.fillStyle = '#eef1f7'; ctx.font = '12px sans-serif'; ctx.fillText('click the gap', slot.x + 18, 26);
            }
        });
    };

    // ------------------------------------------------------------------
    // dial: safe dial. Turn RIGHT to the first number, LEFT to the second, RIGHT to
    // the third (A/D, arrows or mouse wheel). Watch for the click, press SPACE to set it.
    //   opts: numbers (3)
    // ------------------------------------------------------------------
    Games.dial = (o, api) => {
        const count = clamp(o.numbers || 3, 2, 4);
        const combo = Array.from({ length: count }, () => Math.floor(rand(0, 100)));
        const tol = o.difficulty < 0.5 ? 1 : 0;
        const loud = o.difficulty < 0.7;
        api.hint(o.hint || 'Turn the dial and watch the light. When it clicks, press SPACE to set the number.');
        api.keys('<kbd>A</kbd><kbd>D</kbd> / wheel turn &nbsp; <kbd>SPACE</kbd> set &nbsp; <kbd>ESC</kbd> stop');
        const wrap = el('div', 'dial-wrap');
        const dial = el('div', 'dial');
        const face = el('div', 'dial-face');
        for (let i = 0; i < 100; i += 2) {
            const t = el('div', 'tick' + (i % 10 === 0 ? ' big' : ''));
            t.style.transform = `rotate(${i * 3.6}deg)`;
            if (i % 10 === 0) t.innerHTML = `<span style="transform: rotate(${-i * 3.6}deg)">${i}</span>`;
            face.appendChild(t);
        }
        dial.append(face, el('div', 'dial-mark'));
        const side = el('div', 'dial-side');
        side.innerHTML = '<div class="light" id="dial-light"></div><div class="big" id="dial-num">0</div><div id="dial-step"></div><div class="combo" id="dial-combo"></div>';
        wrap.append(dial, side);
        api.stage.appendChild(wrap);
        let num = 0, step = 0, lastDir = 0, clickT = 0;
        const need = () => (step % 2 === 0 ? 1 : -1); // 1 = right (up), -1 = left (down)
        const render = () => {
            face.style.transform = `rotate(${-num * 3.6}deg)`;
            side.querySelector('#dial-num').textContent = String(num).padStart(2, '0');
            side.querySelector('#dial-step').textContent = step < count ? `Turn ${need() > 0 ? 'RIGHT' : 'LEFT'} to number ${step + 1}` : '';
            side.querySelector('#dial-combo').textContent = combo.slice(0, step).map((c) => String(c).padStart(2, '0')).join(' - ');
        };
        const turn = (dir) => {
            num = (num + dir + 100) % 100;
            lastDir = dir;
            const d = Math.min(Math.abs(num - combo[step]), 100 - Math.abs(num - combo[step]));
            if (d <= tol && dir === need()) {
                clickT = loud ? 0.5 : 0.18;
            }
            render();
        };
        api.on('key', (e) => {
            if (e.key === 'd' || e.key === 'ArrowRight' || e.key === 'ArrowUp') turn(1);
            if (e.key === 'a' || e.key === 'ArrowLeft' || e.key === 'ArrowDown') turn(-1);
        });
        api.on('wheel', (e) => turn(e.deltaY < 0 ? 1 : -1));
        api.on('press', () => {
            const d = Math.min(Math.abs(num - combo[step]), 100 - Math.abs(num - combo[step]));
            if (d <= tol && lastDir === need()) {
                step++;
                if (step >= count) return api.finish({ success: true, quality: count / (count + api.mistakes) });
                render();
            } else {
                api.mistake();
            }
        });
        api.loop((dt) => {
            clickT = Math.max(0, clickT - dt);
            const l = side.querySelector('#dial-light');
            l.style.opacity = clickT > 0 ? (loud ? 1 : 0.45) : 0.12;
        });
        render();
    };

    // ------------------------------------------------------------------
    // keycut: grind each cut of the blank to match the original key. Hold SPACE to
    // grind the selected cut (←/→ to pick). You can't add metal back: overcut = mistake.
    //   opts: cuts (5)
    // ------------------------------------------------------------------
    Games.keycut = (o, api) => {
        const n = clamp(o.cuts || 5, 3, 7);
        const tol = lerp(0.07, 0.035, o.difficulty);
        const speed = lerp(0.35, 0.6, o.difficulty);
        const target = Array.from({ length: n }, () => Math.round(rand(2, 9)) / 10);
        const cut = Array(n).fill(0);
        api.hint(o.hint || 'Match the original key. Pick a cut with ←/→ and hold SPACE to grind it down. You can\'t put metal back.');
        api.keys('<kbd>←</kbd><kbd>→</kbd> cut &nbsp; <kbd>HOLD SPACE</kbd> grind &nbsp; <kbd>ESC</kbd> stop');
        const ns = 'http://www.w3.org/2000/svg';
        const mk = (label) => {
            const box = el('div', 'key-row');
            box.innerHTML = `<div class="key-label">${label}</div>`;
            const svg = document.createElementNS(ns, 'svg');
            svg.setAttribute('viewBox', '0 0 420 70');
            svg.setAttribute('class', 'key-svg');
            const path = document.createElementNS(ns, 'path');
            svg.appendChild(path);
            box.appendChild(svg);
            api.stage.appendChild(box);
            return { svg, path };
        };
        const orig = mk('Original');
        const blank = mk('Your copy');
        const markers = [];
        for (let i = 0; i < n; i++) {
            const r = document.createElementNS(ns, 'rect');
            r.setAttribute('class', 'cut-sel');
            blank.svg.appendChild(r);
            markers.push(r);
        }
        const shape = (depths) => {
            // a key blade: bow on the left, cuts along the top edge
            let d = 'M10 10 H90 ';
            const x0 = 100, w = 300 / n;
            depths.forEach((dep, i) => {
                const y = 10 + dep * 34;
                d += `L${x0 + i * w + w * 0.2} ${y} L${x0 + i * w + w * 0.8} ${y} `;
            });
            d += 'L410 30 L410 60 L90 60 L10 60 Z';
            return d;
        };
        orig.path.setAttribute('d', shape(target));
        orig.path.setAttribute('class', 'key-orig');
        blank.path.setAttribute('class', 'key-blank');
        let sel = 0, grinding = false;
        const render = () => {
            blank.path.setAttribute('d', shape(cut));
            const w = 300 / n;
            markers.forEach((m, i) => {
                m.setAttribute('x', 100 + i * w + 2); m.setAttribute('y', 2); m.setAttribute('width', w - 4); m.setAttribute('height', 66);
                const ok = Math.abs(cut[i] - target[i]) <= tol;
                m.setAttribute('class', 'cut-sel' + (i === sel ? ' on' : '') + (ok ? ' ok' : ''));
            });
        };
        render();
        api.on('key', (e) => {
            if (grinding) return;
            if (e.key === 'ArrowLeft' || e.key === 'a') sel = (sel + n - 1) % n;
            if (e.key === 'ArrowRight' || e.key === 'd') sel = (sel + 1) % n;
            render();
        });
        markers.forEach((m, i) => m.addEventListener('mousedown', () => { if (!grinding) { sel = i; render(); } }));
        api.on('press', () => { grinding = true; });
        api.on('release', () => {
            grinding = false;
            if (cut.every((c, i) => Math.abs(c - target[i]) <= tol)) api.finish({ success: true, quality: n / (n + api.mistakes * 1.5) });
        });
        api.loop((dt) => {
            if (!grinding) return;
            cut[sel] = Math.min(1, cut[sel] + speed * dt);
            if (cut[sel] > target[sel] + tol) {
                grinding = false;
                cut[sel] = target[sel]; // the ruined cut is filed back by hand, but it costs you
                api.mistake();
            }
            render();
        });
        blank.svg.classList.add('hold-area');
    };

    // ------------------------------------------------------------------
    // change: a passenger pays cash, give the right change.
    //   opts: fares ([2.5, 3, 3.75]), count (1)
    // ------------------------------------------------------------------
    Games.change = (o, api) => {
        const fares = o.fares || [2.5, 2.75, 3, 3.25, 3.5, 3.75];
        const bills = [5, 10, 20];
        let left = o.count || 1, served = 0;
        const coins = [[10, '$10'], [5, '$5'], [1, '$1'], [0.25, '25¢'], [0.1, '10¢'], [0.05, '5¢']];
        api.hint(o.hint || 'Give the passenger the right change, then press Give change (ENTER).');
        api.keys('<kbd>CLICK</kbd> add money &nbsp; <kbd>ENTER</kbd> give &nbsp; <kbd>ESC</kbd> stop');
        const top = el('div', 'till-top');
        const tray = el('div', 'till-tray');
        const grid = el('div', 'till-grid');
        coins.forEach(([v, label]) => {
            const b = el('button', 'btn coin', label);
            b.addEventListener('click', () => { given = Math.round((given + v) * 100) / 100; draw(); });
            grid.appendChild(b);
        });
        const actions = el('div', 'till-actions');
        const clear = el('button', 'btn', 'Clear');
        const give = el('button', 'btn primary-btn', 'Give change');
        actions.append(clear, give);
        api.stage.append(top, tray, grid, actions);
        let fare, paid, given;
        const next = () => {
            fare = fares[Math.floor(Math.random() * fares.length)];
            paid = bills.filter((b) => b > fare)[Math.floor(Math.random() * 2)] || 5;
            given = 0;
            draw();
        };
        const draw = () => {
            top.innerHTML = `<div>Fare <b>$${fare.toFixed(2)}</b></div><div>Paid with <b>$${paid}</b></div><div class="muted">${served + 1} / ${served + left}</div>`;
            tray.innerHTML = `Change given: <b>$${given.toFixed(2)}</b>`;
        };
        clear.addEventListener('click', () => { given = 0; draw(); });
        const submit = () => {
            const want = Math.round((paid - fare) * 100) / 100;
            if (Math.abs(given - want) < 0.001) {
                served++; left--;
                tray.classList.remove('flash-good'); void tray.offsetWidth; tray.classList.add('flash-good');
                if (left <= 0) return api.finish({ success: true, quality: served / (served + api.mistakes) });
                next();
            } else {
                tray.classList.remove('flash-bad'); void tray.offsetWidth; tray.classList.add('flash-bad');
                if (!api.mistake()) { given = 0; draw(); }
            }
        };
        give.addEventListener('click', submit);
        api.on('enter', submit);
        next();
    };

    // ------------------------------------------------------------------
    // pass: check a bus pass. Accept (A) or reject (R).
    //   opts: zone ('City'), today ('2026-11-02'), fakeChance (0.35)
    //   returns success = the right call, accepted = what the player chose
    // ------------------------------------------------------------------
    Games.pass = (o, api) => {
        const zones = ['City', 'Airport', 'Vinewood', 'County'];
        const zone = o.zone || 'City';
        const today = o.today ? new Date(o.today + 'T12:00:00') : new Date();
        const faces = ['🧔', '👩', '👨‍🦰', '👩‍🦱', '👴', '👵', '🧑‍🦲', '👱‍♀️', '👨‍🦳', '🧑'];
        const first = ['Alex', 'Sam', 'Jordan', 'Casey', 'Morgan', 'Riley', 'Taylor', 'Jamie', 'Drew', 'Quinn'];
        const last = ['Rivera', 'Chen', 'Okafor', 'Novak', 'Haddad', 'Silva', 'Brooks', 'Kowalski', 'Mendes', 'Price'];
        const face = faces[Math.floor(Math.random() * faces.length)];
        const card = {
            name: `${first[Math.floor(Math.random() * 10)]} ${last[Math.floor(Math.random() * 10)]}`,
            face, zones: [zone, zones[Math.floor(Math.random() * zones.length)]].filter((v, i, a) => a.indexOf(v) === i),
            expires: new Date(today.getTime() + rand(5, 200) * 864e5), holo: true,
        };
        let fake = null;
        if (Math.random() < (o.fakeChance ?? 0.35)) {
            fake = ['expired', 'zone', 'holo', 'photo'][Math.floor(Math.random() * 4)];
            if (fake === 'expired') card.expires = new Date(today.getTime() - rand(1, 60) * 864e5);
            if (fake === 'zone') card.zones = zones.filter((z) => z !== zone).slice(0, 1 + Math.floor(Math.random() * 2));
            if (fake === 'holo') card.holo = false;
            if (fake === 'photo') { let f; do { f = faces[Math.floor(Math.random() * faces.length)]; } while (f === face); card.face = f; }
        }
        const fmt = (d) => d.toISOString().slice(0, 10);
        api.hint(o.hint || `Route zone: ${zone}. Today: ${fmt(today)}. Check the date, the zone, the hologram and the photo.`);
        api.keys('<kbd>A</kbd> accept &nbsp; <kbd>R</kbd> reject &nbsp; <kbd>ESC</kbd> stop');
        const row = el('div', 'pass-row');
        row.innerHTML = `
            <div class="passenger"><div class="face">${face}</div><div class="muted small">Passenger</div></div>
            <div class="pass-card">
                <div class="pass-head">LS TRANSIT · MONTHLY PASS ${card.holo ? '<span class="holo">✦</span>' : ''}</div>
                <div class="pass-body">
                    <div class="face small-face">${card.face}</div>
                    <div>
                        <div class="pass-name">${esc(card.name)}</div>
                        <div class="muted small">Zones: <b>${card.zones.join(', ')}</b></div>
                        <div class="muted small">Valid until: <b>${fmt(card.expires)}</b></div>
                    </div>
                </div>
            </div>`;
        const actions = el('div', 'till-actions');
        const rej = el('button', 'btn', 'Reject (R)');
        const acc = el('button', 'btn primary-btn', 'Accept (A)');
        actions.append(rej, acc);
        api.stage.append(row, actions);
        const decide = (accept) => {
            const right = accept === (fake === null);
            api.finish({ success: right, quality: right ? 1 : 0, accepted: accept, fake: fake || false });
        };
        acc.addEventListener('click', () => decide(true));
        rej.addEventListener('click', () => decide(false));
        api.on('key', (e) => {
            if (e.key === 'a' || e.key === 'A') decide(true);
            if (e.key === 'r' || e.key === 'R') decide(false);
        });
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
