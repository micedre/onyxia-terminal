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

  // --- Glisser-déposer de fichiers (trzsz) --------------------------------
  // Au dépôt, trzsz.js envoie Ctrl+C puis « trz » au panneau actif, ce qui
  // casse Neovim ou le programme en cours. On remplace ce Ctrl+C par une
  // séquence liée dans tmux (User0) qui ouvre un panneau de réception dans le
  // dossier du panneau actif : le « trz » qui suit arrive dans ce panneau.
  var DROP_KEY = "\x1b[7999~";
  var paneDir = "";

  // Le filtre trzsz est dans l'addon zmodem de ttyd, chargé dans xterm.js à
  // chaque connexion (champs privés : on le cherche dans les objets du terminal)
  function findTrzsz(t) {
    var found = null;
    Object.keys(t).forEach(function (k) {
      var v = t[k];
      if (!v || typeof v !== "object") { return; }
      Object.keys(v).forEach(function (l) {
        if (!Array.isArray(v[l])) { return; }
        v[l].forEach(function (a) {
          if (a && a.instance && a.instance.trzszFilter) { found = a.instance.trzszFilter; }
        });
      });
    });
    return found;
  }

  function hookTrzsz(filter) {
    var send = filter.sendToServer;
    filter.__onyxia = true;
    filter.sendToServer = function (data) {
      // uploadInterrupting : Ctrl+C envoyé par uploadFiles, pas par l'utilisateur
      send.call(filter, data === "\x03" && filter.uploadInterrupting ? DROP_KEY : data);
    };
  }

  function dirLabel() {
    return paneDir ? paneDir.replace(/^\/home\/[^/]+/, "~") : "le dossier du panneau actif";
  }

  var veil = null, dragDepth = 0;
  function showVeil(on) {
    if (!veil) {
      veil = document.createElement("div");
      veil.style.cssText = "position:fixed;inset:0;z-index:999;display:none;align-items:center;justify-content:center;" +
        "background:rgba(30,120,220,.18);border:3px dashed rgba(30,120,220,.8);pointer-events:none;" +
        "font:16px system-ui,sans-serif;color:#fff;text-shadow:0 1px 3px #000";
      document.body.appendChild(veil);
    }
    veil.textContent = "Déposer pour envoyer dans " + dirLabel();
    veil.style.display = on ? "flex" : "none";
  }

  function hasFiles(e) {
    return e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types || [], "Files") >= 0;
  }

  document.addEventListener("dragenter", function (e) {
    if (hasFiles(e)) { dragDepth++; showVeil(true); }
  });
  document.addEventListener("dragleave", function (e) {
    if (hasFiles(e) && --dragDepth <= 0) { dragDepth = 0; showVeil(false); }
  });
  // Phase de capture : avant le gestionnaire de ttyd sur .xterm
  document.addEventListener("drop", function (e) {
    dragDepth = 0;
    showVeil(false);
    var t = window.term;
    if (!hasFiles(e) || !t || !e.target.closest || !e.target.closest(".xterm")) { return; }
    var filter = t.__onyxiaTrzsz;
    if (filter && filter.isTransferringFiles && filter.isTransferringFiles()) {
      toast("Un transfert est déjà en cours");
      return;
    }
    if (!filter && t.input) { t.input(DROP_KEY); }   // repli (autre version de ttyd) : sans garantie d'ordre
    toast("Envoi vers " + dirLabel() + "…");
  }, true);

  function install(t) {
    t.__onyxia = true;
    t.onTitleChange(function (title) { paneDir = title; });
    t.parser.registerOscHandler(52, onOsc52);
    // Ctrl+V : laisser le navigateur produire son évènement « paste », que
    // xterm.js colle (en mode bracketed paste) au lieu d'envoyer ^V
    t.attachCustomKeyEventHandler(function (e) {
      return !(e.type === "keydown" && e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey &&
               (e.key === "v" || e.key === "V"));
    });
  }

  // ttyd peut recréer le terminal ou l'addon trzsz (reconnexion) : on vérifie régulièrement
  setInterval(function () {
    var t = window.term;
    if (t && t.parser && !t.__onyxia) { install(t); }
    var f = t && t.__onyxia && findTrzsz(t);
    if (f && typeof f.sendToServer === "function" && !f.__onyxia) { hookTrzsz(f); t.__onyxiaTrzsz = f; }
  }, 500);

  // --- Clic droit -----------------------------------------------------------
  // Le menu de tmux suffit : on masque celui du navigateur (Maj+clic droit le garde)
  document.addEventListener("contextmenu", function (e) {
    if (!e.shiftKey && e.target.closest && e.target.closest(".xterm")) { e.preventDefault(); }
  });
})();
