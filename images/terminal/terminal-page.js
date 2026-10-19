// Script injecté dans la page de ttyd par start.sh (sur window.term, exposé par ttyd).
(function () {
  // --- Polices --------------------------------------------------------------
  // xterm.js mesure la largeur des cellules à l'ouverture, souvent avant le
  // chargement des polices : on les précharge puis on force une nouvelle mesure.
  var f = "JetBrains Mono Web";
  Promise.all([400, 700].map(function (w) { return document.fonts.load(w + ' 14px "' + f + '"'); })
    .concat(document.fonts.load('14px "Symbols Nerd Font Mono"', "")))
    .catch(function () {})
    .then(function fix() {
      var t = window.term;
      if (!t || !t.options) { return setTimeout(fix, 100); }
      var ff = t.options.fontFamily;
      t.options.fontFamily = "monospace";
      t.options.fontFamily = ff;
      if (t.fit) { t.fit(); }
    });

  // --- Presse-papiers -------------------------------------------------------
  function toast(text) {
    var el = document.getElementById("onyxia-toast");
    if (!el) {
      el = document.createElement("div");
      el.id = "onyxia-toast";
      el.style.cssText = "position:fixed;top:12px;right:12px;z-index:1000;padding:6px 12px;border-radius:6px;" +
        "background:rgba(40,40,50,.9);color:#fff;font:13px system-ui,sans-serif;pointer-events:none;transition:opacity .3s";
      document.body.appendChild(el);
    }
    el.textContent = text;
    el.style.opacity = "1";
    clearTimeout(el._t);
    el._t = setTimeout(function () { el.style.opacity = "0"; }, 1000);
  }

  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.cssText = "position:fixed;top:-1000px;opacity:0";
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta);
    if (window.term) { window.term.focus(); }
    return ok;
  }

  function copy(text) {
    var done = function () { toast("Copié"); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { if (fallbackCopy(text)) { done(); } });
    } else if (fallbackCopy(text)) {
      done();
    }
  }

  // OSC 52 (« ESC ] 52 ; c ; base64 BEL ») : envoyé par tmux à chaque copie
  // (sélection à la souris, y en mode copie) et par Neovim
  function onOsc52(data) {
    var i = data.indexOf(";");
    var b64 = i < 0 ? "" : data.slice(i + 1);
    if (!b64 || b64 === "?") { return true; }   // lecture du presse-papiers : non prise en charge
    try {
      var bin = atob(b64), bytes = new Uint8Array(bin.length);
      for (var k = 0; k < bin.length; k++) { bytes[k] = bin.charCodeAt(k); }
      copy(new TextDecoder().decode(bytes));
    } catch (e) {}
    return true;
  }

  function install(t) {
    t.__onyxia = true;
    t.parser.registerOscHandler(52, onOsc52);
    // Ctrl+V : laisser le navigateur produire son évènement « paste », que
    // xterm.js colle (en mode bracketed paste) au lieu d'envoyer ^V
    t.attachCustomKeyEventHandler(function (e) {
      return !(e.type === "keydown" && e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey &&
               (e.key === "v" || e.key === "V"));
    });
  }

  // ttyd peut recréer le terminal (reconnexion) : on vérifie régulièrement
  setInterval(function () {
    var t = window.term;
    if (t && t.parser && !t.__onyxia) { install(t); }
  }, 500);

  // --- Clic droit -----------------------------------------------------------
  // Le menu de tmux suffit : on masque celui du navigateur (Maj+clic droit le garde)
  document.addEventListener("contextmenu", function (e) {
    if (!e.shiftKey && e.target.closest && e.target.closest(".xterm")) { e.preventDefault(); }
  });
})();
