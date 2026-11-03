(() => {
    'use strict';

    // The phone loads this page from https://cfx-nui-<resource>/html/app/index.html
    const hostMatch = location.hostname.match(/^cfx-nui-(.+)$/);
    const RESOURCE = hostMatch ? hostMatch[1] : null;
    const IN_GAME = !!RESOURCE;

    async function nui(name, data = {}) {
        if (!IN_GAME) return Mock.handle(name, data);
        try {
            const res = await fetch(`https://${RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (e) {
            return { ok: false, error: 'Connection error' };
        }
    }

    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    let currency = '$';
    const money = (n) => currency + Math.floor(Number(n) || 0).toLocaleString('en-US');
    const dur = (s) => {
        s = Math.max(0, Math.floor(s || 0));
        if (s >= 3600) return `${Math.floor(s / 3600)}h ${String(Math.floor(s % 3600 / 60)).padStart(2, '0')}m`;
        if (s >= 60) return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s`;
        return `${s}s`;
    };
    const ICONS = { utensils: '🌮', 'file-contract': '📄', 'key': '🔑', wrench: '🔧', 'screwdriver-wrench': '🔧', bus: '🚌', key: '🔑', car: '🚗', 'car-side': '🚗', truck: '🚚', 'truck-pickup': '🛻', trash: '🗑️', box: '📦' };
    const icon = (name) => ICONS[name] || '💼';

    let toastTimer;
    function toast(msg, type) {
        const t = $('toast');
        t.textContent = msg;
        t.className = 'toast ' + (type === 'error' ? 'err' : 'ok');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => t.classList.add('hidden'), 3200);
    }

    // ------------------------------------------------------------------
    // State + rendering
    // ------------------------------------------------------------------
    let data = null;
    let view = 'jobs';
    let ratedId = null;

    function levelPct(l) {
        if (!l || !l.next) return 100;
        return Math.round((l.xp - l.current) / Math.max(1, l.next - l.current) * 100);
    }

    function renderJobs() {
        const list = $('jobs-list');
        const jobs = (data && data.jobs) || [];
        if (!jobs.length) {
            list.innerHTML = '<div class="empty"><div class="big">🌙</div>Nobody is hiring right now.<br>Check back later.</div>';
            return;
        }
        list.innerHTML = jobs.map((j) => `
            <div class="card">
                <div class="card-row">
                    <div class="icon">${icon(j.icon)}</div>
                    <div class="grow">
                        <div class="title">${esc(j.label)}</div>
                        <div class="sub">Level ${j.level.level}${j.level.next ? ` · ${j.level.xp}/${j.level.next} XP` : ' · max'}${j.rating ? ` · ★ ${j.rating.toFixed(1)}` : ''}</div>
                    </div>
                    ${j.active ? '<span class="chip good">On shift</span>' : ''}
                </div>
                <div class="levelbar"><div style="width:${levelPct(j.level)}%"></div></div>
                <div class="desc">${esc(j.description || '')}</div>
                <div class="chips">
                    ${j.vehicle ? `<span class="chip">${esc(j.vehicle)} · ${money(j.deposit)} deposit</span>` : '<span class="chip">No vehicle needed</span>'}
                    <span class="chip">${j.onDuty} on shift</span>
                    ${j.completed ? `<span class="chip">${j.completed} done · ${money(j.earned)}</span>` : ''}
                </div>
                <div class="actions">
                    <button class="btn primary" data-gps="${j.depot.x},${j.depot.y}">Set GPS to depot</button>
                </div>
            </div>`).join('');
    }

    function renderShift() {
        const box = $('shift-box');
        const s = data && data.shift;
        $('shift-dot').classList.toggle('hidden', !(s && s.queue && s.queue.some((r) => r.status === 'open')));
        if (!s) {
            box.innerHTML = '<div class="empty"><div class="big">🧰</div>You are not on a shift.<br>Pick a job in <b>Jobs</b> and head to its depot.</div>';
            return;
        }
        let queue = '';
        if (s.takesRequests) {
            const items = (s.queue || []).map((r) => `
                <div class="card">
                    <div class="card-row">
                        <div class="grow">
                            <div class="title">${esc(r.requesterName)}${r.assignedToMe ? ' <span class="chip warn">Yours</span>' : ''}</div>
                            <div class="sub">${r.distance != null ? r.distance + 'm away · ' : ''}${money(r.price)} · waiting ${dur(r.age)}${r.plate ? ' · ' + esc(r.plate) : ''}</div>
                            ${r.note ? `<div class="desc">"${esc(r.note)}"</div>` : ''}
                        </div>
                    </div>
                    <div class="actions">
                        ${r.assignedToMe
                            ? `<button class="btn" data-gps="${r.coords ? r.coords.x + ',' + r.coords.y : ''}">GPS</button>`
                            : `<button class="btn primary" data-accept="${r.id}">Accept</button>`}
                    </div>
                </div>`).join('');
            queue = `<div class="section-title">Player requests</div>
                <div class="list">${items || '<div class="card muted small">No player requests right now. You will get NPC calls in the meantime.</div>'}</div>`;
        }
        box.innerHTML = `
            <div class="section-title">Current shift</div>
            <div class="card">
                <div class="card-row">
                    <div class="grow">
                        <div class="title">${esc(s.label)}</div>
                        <div class="sub">On shift for ${dur(s.duration)}${s.vehicle ? ' · ' + esc(s.vehicle) : ''}</div>
                    </div>
                    <span class="chip good">Lvl ${s.level.level}</span>
                </div>
                <div class="levelbar"><div style="width:${levelPct(s.level)}%"></div></div>
                ${s.status ? `<div class="status-line">${esc(s.status)}</div>` : ''}
                <div class="stats">
                    <div class="stat"><b>${money(s.earned)}</b><span>Earned</span></div>
                    <div class="stat"><b>${s.tasks}</b><span>Jobs</span></div>
                    <div class="stat"><b>${s.deposit ? money(s.deposit) : '-'}</b><span>Deposit</span></div>
                </div>
                <div class="actions"><button class="btn danger" id="end-shift">End shift</button></div>
                <div class="sub" style="margin-top:8px">Return the vehicle to the depot first to get your deposit back.</div>
            </div>
            ${queue}`;
    }

    function stepIndex(status) {
        return { open: 0, assigned: 1, working: 2, npc: 2 }[status] ?? 0;
    }

    function renderHelp() {
        const box = $('help-box');
        const r = data && data.request;
        if (r) {
            const i = stepIndex(r.status);
            const who = r.status === 'npc' ? 'An NPC is on the way'
                : r.workerName ? `${esc(r.workerName)}${r.workerRating ? ` · ★ ${Number(r.workerRating).toFixed(1)}` : ''}` : 'Looking for a worker…';
            box.innerHTML = `
                <div class="section-title">Your request</div>
                <div class="card">
                    <div class="title">${esc(r.label)}</div>
                    <div class="sub">${money(r.price)} held until the job is done${r.plate ? ' · ' + esc(r.plate) : ''}</div>
                    <div class="steps">
                        <div class="step ${i >= 0 ? 'on' : ''}"><i></i>Sent</div>
                        <div class="step ${i >= 1 ? 'on' : ''}"><i></i>On the way</div>
                        <div class="step ${i >= 2 ? 'on' : ''}"><i></i>Working</div>
                    </div>
                    <div class="status-line">${who}${r.workerDistance != null ? ` · ${r.workerDistance}m away` : ''}</div>
                    <div class="actions">
                        <button class="btn danger" id="cancel-req" ${r.status === 'working' || r.status === 'npc' ? 'disabled' : ''}>Cancel request</button>
                    </div>
                </div>`;
            return;
        }
        const services = ((data && data.jobs) || []).filter((j) => j.requests);
        if (!services.length) {
            box.innerHTML = '<div class="empty"><div class="big">📵</div>No services are available right now.</div>';
            return;
        }
        box.innerHTML = '<div class="section-title">Request a service</div><div class="list">' + services.map((j) => `
            <div class="card">
                <div class="card-row">
                    <div class="icon">${icon(j.icon)}</div>
                    <div class="grow">
                        <div class="title">${esc(j.requests.label)}</div>
                        <div class="sub">${j.onDuty > 0 ? `${j.onDuty} worker${j.onDuty === 1 ? '' : 's'} on duty · ${j.requests.types ? 'from ' : ''}${money(j.requests.price)}` : (j.requests.npcPrice ? `No workers on duty · NPC ${money(j.requests.npcPrice)}` : 'No workers on duty')}</div>
                    </div>
                </div>
                ${j.requests.description ? `<div class="desc">${esc(j.requests.description)}</div>` : ''}
                <div class="actions">
                    <button class="btn primary" data-request="${esc(j.id)}" ${j.onDuty === 0 && !j.requests.npcPrice ? 'disabled' : ''}>Request</button>
                </div>
            </div>`).join('') + '</div>';
    }

    function render() {
        if (!data) return;
        $('hello').textContent = data.name ? `Hi ${data.name.split(' ')[0]}, find work around the city` : 'Find work around the city';
        renderJobs();
        renderShift();
        renderHelp();
        if (data.rating && data.rating.id !== ratedId && $('sheet').classList.contains('hidden')) openRating(data.rating);
    }

    async function refresh() {
        const res = await nui('app:data');
        if (!res || res.ok === false) return;
        if (res.currency) currency = res.currency;
        data = res;
        render();
    }

    // ------------------------------------------------------------------
    // Sheets (request form, rating)
    // ------------------------------------------------------------------
    function openSheet(html) {
        $('sheet').innerHTML = html;
        $('sheet').classList.remove('hidden');
        $('sheet-backdrop').classList.remove('hidden');
    }
    function closeSheet() {
        $('sheet').classList.add('hidden');
        $('sheet-backdrop').classList.add('hidden');
    }
    $('sheet-backdrop').addEventListener('click', closeSheet);

    function openRequest(jobId) {
        const j = data.jobs.find((x) => x.id === jobId);
        if (!j) return;
        const npc = j.onDuty === 0;
        const types = j.requests.types || [{ id: null, label: j.requests.label, price: j.requests.price, npcPrice: j.requests.npcPrice, needsVehicle: j.requests.needsVehicle }];
        let picked = types[0];
        const priceOf = (t) => (npc ? t.npcPrice : t.price);
        const usable = (t) => !npc || t.npcPrice != null;
        picked = types.find(usable) || types[0];
        const typeList = types.length > 1 ? `<div class="types">${types.map((t, i) => `
            <button class="type ${t === picked ? 'on' : ''}" data-type="${i}" ${usable(t) ? '' : 'disabled'}>
                <span>${esc(t.label)}${t.description ? `<small>${esc(t.description)}</small>` : ''}</span>
                <b>${usable(t) ? money(priceOf(t)) : 'n/a'}</b>
            </button>`).join('')}</div>` : '';
        const info = () => `${npc
            ? `Nobody is on duty, so an NPC will come. It costs <b>${money(priceOf(picked))}</b>.`
            : `<b>${money(priceOf(picked))}</b> is held until the job is done, and refunded if you cancel before work starts.`}
            ${picked.needsVehicle ? '<br>Stand next to the vehicle that needs help.' : ''}`;
        openSheet(`
            <h3>${esc(j.requests.label)}</h3>
            ${typeList}
            <div class="sub muted" id="req-info">${info()}</div>
            <textarea id="req-note" maxlength="120" placeholder="Anything the worker should know? (optional)"></textarea>
            <div class="actions">
                <button class="btn" id="sheet-cancel">Back</button>
                <button class="btn primary" id="sheet-send">Request · ${money(priceOf(picked))}</button>
            </div>`);
        $('sheet').querySelectorAll('[data-type]').forEach((b) => b.addEventListener('click', () => {
            picked = types[Number(b.dataset.type)];
            $('sheet').querySelectorAll('[data-type]').forEach((x) => x.classList.toggle('on', x === b));
            $('req-info').innerHTML = info();
            $('sheet-send').textContent = `Request · ${money(priceOf(picked))}`;
        }));
        $('sheet-cancel').onclick = closeSheet;
        $('sheet-send').onclick = async () => {
            $('sheet-send').disabled = true;
            const res = await nui('app:request', { job: jobId, type: picked.id, note: $('req-note').value });
            closeSheet();
            if (res.ok) { toast('Request sent'); showView('help'); }
            else toast(res.error, 'error');
            refresh();
        };
    }

    function openRating(r) {
        let stars = 0;
        openSheet(`
            <h3>How did ${esc(r.workerName || 'they')} do?</h3>
            <div class="sub muted">${esc(r.jobLabel)}. Good ratings put them first in line for future requests.</div>
            <div class="stars" id="stars">${[1, 2, 3, 4, 5].map((n) => `<button data-star="${n}">★</button>`).join('')}</div>
            <div class="actions">
                <button class="btn" id="sheet-skip">Skip</button>
                <button class="btn primary" id="sheet-rate" disabled>Send rating</button>
            </div>`);
        $('stars').addEventListener('click', (e) => {
            const b = e.target.closest('[data-star]');
            if (!b) return;
            stars = Number(b.dataset.star);
            $('stars').querySelectorAll('button').forEach((x) => x.classList.toggle('on', Number(x.dataset.star) <= stars));
            $('sheet-rate').disabled = false;
        });
        $('sheet-skip').onclick = () => { ratedId = r.id; closeSheet(); };
        $('sheet-rate').onclick = async () => {
            ratedId = r.id;
            const res = await nui('app:rate', { id: r.id, stars });
            closeSheet();
            toast(res.ok ? 'Thanks for the rating!' : (res.error || 'Could not save the rating'), res.ok ? 'ok' : 'error');
            refresh();
        };
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    function showView(name) {
        view = name;
        document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.view === name));
        document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === 'view-' + name));
    }
    document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => showView(t.dataset.view)));

    document.addEventListener('click', async (e) => {
        const gps = e.target.closest('[data-gps]');
        if (gps && gps.dataset.gps) {
            const [x, y] = gps.dataset.gps.split(',').map(Number);
            await nui('app:waypoint', { x, y });
            toast('GPS set');
            return;
        }
        const acc = e.target.closest('[data-accept]');
        if (acc) {
            acc.disabled = true;
            const res = await nui('app:accept', { id: Number(acc.dataset.accept) });
            toast(res.ok ? 'Request accepted. GPS set.' : res.error, res.ok ? 'ok' : 'error');
            refresh();
            return;
        }
        const req = e.target.closest('[data-request]');
        if (req) { openRequest(req.dataset.request); return; }
        if (e.target.id === 'end-shift') {
            e.target.disabled = true;
            const res = await nui('app:endShift');
            toast(res.ok ? 'Shift ended' : res.error, res.ok ? 'ok' : 'error');
            refresh();
            return;
        }
        if (e.target.id === 'cancel-req') {
            e.target.disabled = true;
            const res = await nui('app:cancel');
            toast(res.ok ? 'Request cancelled and refunded' : res.error, res.ok ? 'ok' : 'error');
            refresh();
        }
    });

    // ------------------------------------------------------------------
    // Browser preview (open html/app/index.html directly)
    // ------------------------------------------------------------------
    const Mock = {
        handle(name) {
            if (name === 'app:data') return Promise.resolve(Mock.data);
            return Promise.resolve({ ok: true });
        },
        data: {
            ok: true, currency: '$', name: 'Jamie Rivera',
            jobs: [
                {
                    id: 'roadside', label: 'Roadside Assistance', icon: 'wrench', description: 'Fix flats, jump batteries, refuel and flip cars back over. Players can call you, NPC calls fill the gaps.',
                    depot: { x: 471, y: -1311 }, deposit: 600, vehicle: 'Service Truck', onDuty: 2, active: true, completed: 14, earned: 9850,
                    rating: 4.6, ratingCount: 9, level: { level: 3, xp: 310, current: 250, next: 450 },
                    requests: { label: 'Roadside assistance', description: 'Flat tire, dead battery, out of fuel or stuck? A mechanic comes to you.', price: 400, npcPrice: 650, needsVehicle: true },
                },
                {
                    id: 'locksmith', label: 'Locksmith', icon: 'key', description: 'Get people back into their cars and homes, pick locks, crack safes and cut keys.',
                    depot: { x: 170, y: -1722 }, deposit: 400, vehicle: 'Locksmith Van', onDuty: 1, active: false, completed: 3, earned: 1240,
                    level: { level: 2, xp: 140, current: 100, next: 250 },
                    requests: { label: 'Locksmith', description: 'Locked out of your car or house, or need a spare car key?', price: 200, npcPrice: 350, types: [
                        { id: 'car', label: 'Locked out of my car', description: 'Stand next to your car.', price: 250, npcPrice: 400, needsVehicle: true },
                        { id: 'house', label: 'Locked out of my house', description: 'Stand at your front door.', price: 300, npcPrice: 450 },
                        { id: 'key', label: 'Spare car key', description: 'Stand next to your car.', price: 200, npcPrice: 350, needsVehicle: true },
                    ] },
                },
                {
                    id: 'bus', label: 'Bus Driver', icon: 'bus', description: 'Drive city routes on a timetable. Collect fares, check passes and keep the ride smooth.',
                    depot: { x: 453, y: -600 }, deposit: 1000, vehicle: 'City Bus', onDuty: 0, active: false, completed: 0, earned: 0,
                    level: { level: 1, xp: 0, current: 0, next: 100 },
                },
            ],
            shift: {
                job: 'roadside', label: 'Roadside Assistance', duration: 1520, earned: 2140, tasks: 4, deposit: 600, vehicle: 'Service Truck',
                level: { level: 3, xp: 310, current: 250, next: 450 }, status: 'NPC call: flat tire on Vespucci Blvd (430m)', takesRequests: true,
                queue: [{ id: 7, requesterName: 'Sam Ortiz', distance: 820, price: 400, age: 42, plate: '8ABC123', note: 'Blew a tire near the pier', status: 'open' }],
            },
            request: null,
            rating: null,
        },
    };

    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 5000);
})();
