// nu01 additions on top of Dimension's main.js.

// Language: a visitor's pick (the footer links) is remembered; on a first
// visit to the English page, a browser that prefers one of the other
// languages is sent to its page. Without storage, nothing is remembered and
// nobody is redirected.
(function () {
	var KEY = 'nu01.lang';
	var links = Array.prototype.slice.call(document.querySelectorAll('.langs a'));
	var offered = links.map(function (a) { return a.dataset.lang; });
	try {
		links.forEach(function (a) {
			a.addEventListener('click', function () { localStorage.setItem(KEY, a.dataset.lang); });
		});
		if (document.body.dataset.lang !== 'en' || localStorage.getItem(KEY)) { return; }
		var wanted = (navigator.languages || [navigator.language || ''])
			.map(function (l) { return String(l).slice(0, 2).toLowerCase(); })
			.filter(function (l) { return offered.indexOf(l) >= 0; })[0];
		if (wanted && wanted !== 'en') {
			localStorage.setItem(KEY, wanted);
			location.replace('/' + wanted + '/' + location.hash);
		}
	} catch (e) {}
})();

// The heroes: the line under the description, the background and the
// highlighted nav button rotate every 7 s through Learnware, presence,
// uplink and rbacr. Rotation waits while an article is open or the header
// is hovered or focused, and stops when paused or with reduced motion.
(function () {
	var box = document.querySelector('#header .heroes');
	var heroes = Array.prototype.slice.call(box.querySelectorAll('.hero'));
	var navLinks = Array.prototype.slice.call(document.querySelectorAll('#header nav a'));
	var pause = box.querySelector('.hero-pause');
	var header = document.getElementById('header');
	var bg = document.getElementById('bg');
	var current = 0;
	var stopped = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
	var holding = false;

	// Preload the backgrounds so the swap doesn't flash.
	heroes.forEach(function (hero) { new Image().src = '/images/bg-' + hero.dataset.hero + '.jpg'; });

	function show(index) {
		current = (index + heroes.length) % heroes.length;
		var name = heroes[current].dataset.hero;
		heroes.forEach(function (hero, i) {
			hero.hidden = i !== current;
			hero.classList.toggle('is-active', i === current);
		});
		navLinks.forEach(function (a) { a.classList.toggle('is-current', a.dataset.hero === name); });
		bg.style.setProperty('--hero-bg', 'url("/images/bg-' + name + '.jpg")');
	}

	function updatePause() {
		pause.innerHTML = stopped ? '&#9654;' : '&#10074;&#10074;';
		pause.setAttribute('aria-label', stopped ? box.dataset.play : box.dataset.pause);
	}

	setInterval(function () {
		if (!stopped && !holding && !document.body.classList.contains('is-article-visible')) {
			show(current + 1);
		}
	}, 7000);

	pause.addEventListener('click', function () { stopped = !stopped; updatePause(); });
	header.addEventListener('mouseenter', function () { holding = true; });
	header.addEventListener('mouseleave', function () { holding = false; });
	header.addEventListener('focusin', function () { holding = true; });
	header.addEventListener('focusout', function () { holding = false; });

	// Opening an article shows its hero behind it.
	navLinks.concat(heroes).forEach(function (a) {
		a.addEventListener('click', function () {
			show(heroes.map(function (h) { return h.dataset.hero; }).indexOf(a.dataset.hero));
		});
	});

	var fromHash = heroes.map(function (h) { return h.dataset.hero; }).indexOf(location.hash.slice(1));
	show(fromHash >= 0 ? fromHash : 0);
	updatePause();
})();

// The footer shows the deployed version (version.json, written by the build).
(function () {
	fetch('/version.json', { cache: 'no-cache' })
		.then(function (r) { return r.ok ? r.json() : null; })
		.then(function (info) {
			if (info && info.version) { document.getElementById('version').textContent = 'v' + info.version; }
		})
		.catch(function () {});
})();
