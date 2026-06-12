--[[ Locale.lua — player-facing strings (enUS keys; deDE + ruRU translations).

  ns.L is a lookup table whose __index returns the KEY itself, so every string
  not (yet) translated falls back to English — an incomplete dictionary can
  never break the UI. Keys are the literal English strings (with %s/%d format
  slots where text is composed), applied once at load from GetLocale().

  Scope: the UI layer and local chat messages. Strings that travel OVER THE
  WIRE (e.g. a host's REFUSE reason) are composed on the SENDER and shown
  verbatim — they stay in the host's language by design.

  Poker action verbs stay English in German (Fold/Check/Call/Raise are the
  established terms at German tables); Russian uses the standard
  transliterations. Translated button labels are chosen to FIT the fixed
  button widths.
]]

local ADDON, ns = ...

local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

local DICT = {}

DICT.deDE = {
  -- lobby
  ["Play with:"] = "Spielen mit:",
  ["Guild"] = "Gilde", ["Group"] = "Gruppe",
  ["Tables"] = "Tische",
  ["No tables found — create one below, or Refresh."] = "Keine Tische gefunden — eröffne unten einen oder lade neu.",
  ["Join"] = "Setzen", ["Full"] = "Voll", ["Here"] = "Hier",
  ["Watch"] = "Zusehen", ["Watching"] = "Schaue zu",
  ["Refresh"] = "Laden", ["Stats"] = "Bilanz",
  ["Playing: "] = "Am Tisch: ",
  ["Host: %s"] = "Gastgeber: %s",
  ["Waiting for players — %d seated. Start when ready!"] = "Warten auf Spieler — %d sitzen. Starte, wenn bereit!",
  ["You are hosting (%d seated)."] = "Du bist Gastgeber (%d sitzen).",
  ["Seated at %s's table."] = "Du sitzt an %ss Tisch.",
  ["Seated at %s — waiting for the host to start…"] = "Du sitzt an %s — warte auf den Start…",
  ["Watching %s — every hand is checked as you watch."] = "Du schaust %s zu — jede Hand wird live geprüft.",
  ["Start Game"] = "Starten", ["Need 2+"] = "Mind. 2",
  ["Leave Table"] = "Aufstehen", ["Close Table"] = "Schließen",
  ["Create a table — blinds:"] = "Neuer Tisch — Blinds:",
  ["Create Table"] = "Eröffnen",
  ["Tables deal automatically once 2+ players sit."] = "Gespielt wird automatisch, sobald 2+ Spieler sitzen.",
  -- table window
  ["Blinds %s/%s"] = "Blinds %s/%s",
  [" (rising)"] = " (steigend)",
  ["Stop Watching"] = "Wegsehen",
  ["Pause"] = "Pause", ["Resume"] = "Weiter",
  ["Sit Out"] = "Aussetzen", ["I'm Back"] = "Bin zurück",
  ["Your turn!"] = "Du bist dran!",
  ["Waiting for %s…"] = "Warte auf %s…",
  ["Hand complete — next deal in a moment…"] = "Hand vorbei — gleich wird neu gegeben…",
  ["Hand complete — table paused for a break"] = "Hand vorbei — Tisch macht Pause",
  ["Table paused — back soon!"] = "Tisch pausiert — gleich geht's weiter!",
  ["(break — no clock, finish at leisure)"] = "(Pause — keine Uhr, spielt in Ruhe zu Ende)",
  ["Sitting out — click \"I'm Back\" to be dealt in."] = "Du setzt aus — klicke \"Bin zurück\", um mitzuspielen.",
  ["HALTED"] = "ANGEHALTEN",
  ["watching"] = "Zuschauer",
  ["%s wins +%s"] = "%s gewinnt +%s",
  ["Split pot:  "] = "Geteilter Pot:  ",
  ["bet %s"] = "setzt %s",
  ["%s (you)"] = "%s (du)",
  -- actions (poker verbs stay English at German tables)
  ["Call %s"] = "Call %s",
  ["Checked automatically — no other action was possible."] = "Automatisch gecheckt — keine andere Aktion war möglich.",
  -- trust
  ["Fairness Report"] = "Fairness-Bericht",
  ["Shuffle seed sealed by ALL players' secrets"] = "Misch-Seed durch die Geheimnisse ALLER Spieler versiegelt",
  ["All 52 cards locked (hashed) before any betting"] = "Alle 52 Karten vor jedem Einsatz festgeschrieben (gehasht)",
  ["Every player saw the SAME deck (cross-check)"] = "Alle Spieler sahen DASSELBE Deck (Kreuzprüfung)",
  ["Each revealed card matched its sealed hash"] = "Jede aufgedeckte Karte entsprach ihrem Siegel-Hash",
  ["Full deck re-derived & audited at hand end"] = "Komplettes Deck am Handende nachgerechnet & geprüft",
  ["No one — the dealer included — can know or change the order of the cards. Any tampering trips an instant CHEAT alert for everyone at the table."] =
    "Niemand — auch der Geber nicht — kann die Reihenfolge der Karten kennen oder ändern. Jede Manipulation löst sofort für alle am Tisch einen BETRUGS-Alarm aus.",
  ["fair play: hand verified"] = "Fair Play: Hand verifiziert",
  ["fair play: cards verified"] = "Fair Play: Karten verifiziert",
  ["fair play: deck sealed, verifying…"] = "Fair Play: Deck versiegelt, prüfe…",
  ["fair play: preparing…"] = "Fair Play: Vorbereitung…",
  ["fair play: FAILED"] = "Fair Play: FEHLGESCHLAGEN",
  ["fair play: couldn't verify this hand (missed a broadcast)"] = "Fair Play: Hand nicht prüfbar (Übertragung verpasst)",
  ["Hands fully verified this session: %d"] = "Vollständig geprüfte Hände diese Sitzung: %d",
  ["Clients verify every hand you deal."] = "Die Mitspieler prüfen jede Hand, die du gibst.",
  ["Verification runs during each hand."] = "Die Prüfung läuft während jeder Hand.",
  ["No hand in progress — play one and check back!"] = "Keine Hand im Gange — spiel eine und schau wieder rein!",
  -- stats
  ["Your Poker Record"] = "Deine Poker-Bilanz",
  ["Achievements"] = "Erfolge",
  ["Hands: %s played, %s won (%d%%) — best streak %s"] = "Hände: %s gespielt, %s gewonnen (%d%%) — beste Serie %s",
  ["Net chips: "] = "Chips gesamt: ",
  ["Biggest single-hand win: %s"] = "Größter Gewinn in einer Hand: %s",
  ["Best hand made: %s"] = "Beste gemachte Hand: %s",
  ["Showdowns won: %s   ·   uncontested (bluff) wins: %s"] = "Showdowns gewonnen: %s   ·   unangefochtene (Bluff-)Siege: %s",
  ["Sit & Gos: %s played, %s won%s"] = "Sit & Gos: %s gespielt, %s gewonnen%s",
  ["  (best finish: %d)"] = "  (beste Platzierung: %d)",
  ["Hands dealt as host: %s   ·   hands verified clean: %s"] = "Als Geber ausgeteilt: %s   ·   sauber verifiziert: %s",
  -- chat lines (Init)
  ["loaded — type /azh to open the casino."] = "geladen — tippe /azh, um das Casino zu öffnen.",
  ["Achievement unlocked: %s"] = "Erfolg freigeschaltet: %s",
  ["Blinds up! Level %s: %s/%s"] = "Blinds steigen! Stufe %s: %s/%s",
  ["%s finishes %s."] = "%s belegt Platz %s.",
  ["%s wins the Sit & Go!"] = "%s gewinnt das Sit & Go!",
}

DICT.ruRU = {
  -- lobby
  ["Play with:"] = "Играть с:",
  ["Guild"] = "Гильдия", ["Group"] = "Группа",
  ["Tables"] = "Столы",
  ["No tables found — create one below, or Refresh."] = "Столы не найдены — создайте свой ниже или обновите список.",
  ["Join"] = "Сесть", ["Full"] = "Полон", ["Here"] = "Здесь",
  ["Watch"] = "Смотреть", ["Watching"] = "Смотрю",
  ["Refresh"] = "Поиск", ["Stats"] = "Статы",
  ["Playing: "] = "Играют: ",
  ["Host: %s"] = "Хост: %s",
  ["Waiting for players — %d seated. Start when ready!"] = "Ждём игроков — за столом %d. Начинайте, когда готовы!",
  ["You are hosting (%d seated)."] = "Вы ведёте стол (за столом %d).",
  ["Seated at %s's table."] = "Вы за столом игрока %s.",
  ["Seated at %s — waiting for the host to start…"] = "Вы за столом %s — ждём начала игры…",
  ["Watching %s — every hand is checked as you watch."] = "Вы смотрите %s — каждая раздача проверяется.",
  ["Start Game"] = "Начать", ["Need 2+"] = "Нужно 2+",
  ["Leave Table"] = "Встать", ["Close Table"] = "Закрыть",
  ["Create a table — blinds:"] = "Новый стол — блайнды:",
  ["Create Table"] = "Создать",
  ["Tables deal automatically once 2+ players sit."] = "Раздача идёт автоматически, когда сядут 2+ игрока.",
  -- table window
  ["Blinds %s/%s"] = "Блайнды %s/%s",
  [" (rising)"] = " (растут)",
  ["Stop Watching"] = "Не смотреть",
  ["Pause"] = "Пауза", ["Resume"] = "Дальше",
  ["Sit Out"] = "Пропуск", ["I'm Back"] = "Я здесь",
  ["Your turn!"] = "Ваш ход!",
  ["Waiting for %s…"] = "Ходит %s…",
  ["Hand complete — next deal in a moment…"] = "Раздача окончена — продолжение через миг…",
  ["Hand complete — table paused for a break"] = "Раздача окончена — стол на перерыве",
  ["Table paused — back soon!"] = "Перерыв — скоро продолжим!",
  ["(break — no clock, finish at leisure)"] = "(перерыв — без таймера, доигрывайте спокойно)",
  ["Sitting out — click \"I'm Back\" to be dealt in."] = "Вы пропускаете раздачи — нажмите \"Я здесь\", чтобы вернуться.",
  ["HALTED"] = "ОСТАНОВЛЕНО",
  ["watching"] = "наблюдение",
  ["%s wins +%s"] = "%s выигрывает +%s",
  ["Split pot:  "] = "Делёж банка:  ",
  ["bet %s"] = "ставка %s",
  ["%s (you)"] = "%s (вы)",
  -- actions (standard Russian poker transliterations)
  ["Fold"] = "Фолд", ["Check"] = "Чек", ["Call"] = "Колл",
  ["Call %s"] = "Колл %s",
  ["Raise to"] = "Рейз до", ["Bet"] = "Бет",
  ["Min"] = "Мин", ["Pot"] = "Банк", ["All-in"] = "Олл-ин",
  ["Check/Fold"] = "Чек/Фолд", ["Call any"] = "Колл любой",
  ["Checked automatically — no other action was possible."] = "Автоматический чек — других действий не было.",
  -- trust
  ["Fairness Report"] = "Отчёт о честности",
  ["Shuffle seed sealed by ALL players' secrets"] = "Сид тасовки запечатан секретами ВСЕХ игроков",
  ["All 52 cards locked (hashed) before any betting"] = "Все 52 карты зафиксированы (хешированы) до ставок",
  ["Every player saw the SAME deck (cross-check)"] = "Все игроки видели ОДНУ И ТУ ЖЕ колоду (сверка)",
  ["Each revealed card matched its sealed hash"] = "Каждая открытая карта совпала со своим хешем",
  ["Full deck re-derived & audited at hand end"] = "Вся колода пересчитана и проверена в конце раздачи",
  ["No one — the dealer included — can know or change the order of the cards. Any tampering trips an instant CHEAT alert for everyone at the table."] =
    "Никто — включая дилера — не может знать или менять порядок карт. Любое вмешательство мгновенно поднимает тревогу ЧИТ для всех за столом.",
  ["fair play: hand verified"] = "честная игра: раздача проверена",
  ["fair play: cards verified"] = "честная игра: карты проверены",
  ["fair play: deck sealed, verifying…"] = "честная игра: колода запечатана, проверка…",
  ["fair play: preparing…"] = "честная игра: подготовка…",
  ["fair play: FAILED"] = "честная игра: ПРОВАЛ",
  ["fair play: couldn't verify this hand (missed a broadcast)"] = "честная игра: раздачу не удалось проверить (пропущен пакет)",
  ["Hands fully verified this session: %d"] = "Полностью проверено раздач за сессию: %d",
  ["Clients verify every hand you deal."] = "Игроки проверяют каждую вашу раздачу.",
  ["Verification runs during each hand."] = "Проверка идёт в каждой раздаче.",
  ["No hand in progress — play one and check back!"] = "Раздачи нет — сыграйте и загляните снова!",
  -- stats
  ["Your Poker Record"] = "Ваша покерная статистика",
  ["Achievements"] = "Достижения",
  ["Hands: %s played, %s won (%d%%) — best streak %s"] = "Раздач: %s сыграно, %s выиграно (%d%%) — лучшая серия %s",
  ["Net chips: "] = "Фишки итого: ",
  ["Biggest single-hand win: %s"] = "Крупнейший выигрыш за раздачу: %s",
  ["Best hand made: %s"] = "Лучшая собранная рука: %s",
  ["Showdowns won: %s   ·   uncontested (bluff) wins: %s"] = "Выиграно на вскрытии: %s   ·   без вскрытия (блеф): %s",
  ["Sit & Gos: %s played, %s won%s"] = "Sit & Go: %s сыграно, %s выиграно%s",
  ["  (best finish: %d)"] = "  (лучшее место: %d)",
  ["Hands dealt as host: %s   ·   hands verified clean: %s"] = "Раздано как дилер: %s   ·   проверено чисто: %s",
  -- chat lines (Init)
  ["loaded — type /azh to open the casino."] = "загружен — введите /azh, чтобы открыть казино.",
  ["Achievement unlocked: %s"] = "Достижение получено: %s",
  ["Blinds up! Level %s: %s/%s"] = "Блайнды растут! Уровень %s: %s/%s",
  ["%s finishes %s."] = "%s занимает место: %s.",
  ["%s wins the Sit & Go!"] = "%s выигрывает Sit & Go!",
}

-- place numbers: English ordinals; German "2."; Russian plain numerals
local ORDINAL = {
  deDE = function(n) return n .. "." end,
  ruRU = function(n) return tostring(n) end,
}

-- apply a locale's dictionary (testable seam; called below with the client
-- locale, and again from Init when the player saved an override or switches)
function ns.applyLocale(loc)
  for k in pairs(L) do L[k] = nil end
  local d = DICT[loc]
  if d then for k, v in pairs(d) do L[k] = v end end
  ns.ordinalFn = ORDINAL[loc]
  ns.localeCode = loc
end

function ns.clientLocale()
  return (type(GetLocale) == "function" and GetLocale()) or "enUS"
end

-- the language button's label ("EN"/"DE"/"RU")
function ns.localeShort()
  return ns.localeCode == "deDE" and "DE" or ns.localeCode == "ruRU" and "RU" or "EN"
end

ns.applyLocale(ns.clientLocale())   -- a saved override re-applies at ADDON_LOADED

return L
