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
  -- achievements (names kept evocative; descriptions exact)
  ["First Blood"] = "Erstes Blut", ["Win your first hand"] = "Gewinne deine erste Hand",
  ["On a Roll"] = "Im Lauf", ["Win 10 hands"] = "Gewinne 10 Hände",
  ["Card Shark"] = "Kartenhai", ["Win 100 hands"] = "Gewinne 100 Hände",
  ["Table Regular"] = "Stammgast", ["Play 100 hands"] = "Spiele 100 Hände",
  ["The Grinder"] = "Der Grinder", ["Play 1,000 hands"] = "Spiele 1.000 Hände",
  ["Heater"] = "Lauf", ["Win 5 hands in a row"] = "Gewinne 5 Hände in Folge",
  ["Monster Pot"] = "Monster-Pot", ["Win 500+ chips in one hand"] = "Gewinne 500+ Chips in einer Hand",
  ["Boat Builder"] = "Full-House-Baumeister", ["Make a Full House"] = "Bilde ein Full House",
  ["Quad Damage"] = "Vierling", ["Make Four of a Kind"] = "Bilde einen Vierling",
  ["Royal Line"] = "Königsreihe", ["Make a Straight Flush"] = "Bilde einen Straight Flush",
  ["All-In, All Win"] = "All-in, voll gewonnen", ["Win a hand after going all-in"] = "Gewinne eine Hand nach einem All-in",
  ["Stone Cold Bluffer"] = "Eiskalter Bluffer", ["Win 25 hands without a showdown"] = "Gewinne 25 Hände ohne Showdown",
  ["Closer"] = "Vollstrecker", ["Win a Sit & Go"] = "Gewinne ein Sit & Go",
  ["Dynasty"] = "Dynastie", ["Win 3 Sit & Gos"] = "Gewinne 3 Sit & Gos",
  ["House Dealer"] = "Haus-Geber", ["Deal 50 hands as the host"] = "Gib 50 Hände als Gastgeber",
  ["Trust, but Verify"] = "Vertrauen ist gut, Prüfen ist besser", ["100 hands verified clean"] = "100 Hände sauber verifiziert",
  -- leaderboard
  ["Guild Leaderboard"] = "Gilden-Rangliste",
  ["Sit & Go results seen on this floor."] = "Auf diesem Parkett gesehene Sit & Go-Ergebnisse.",
  ["Player"] = "Spieler", ["Won"] = "Siege", ["Cashed"] = "Plätze", ["Played"] = "Gespielt",
  ["Observed live — not a verified ranking. /azh top reset to clear."] = "Live beobachtet — keine verifizierte Wertung. /azh top reset zum Löschen.",
  ["No tournaments seen yet — host or watch a Sit & Go!"] = "Noch keine Turniere gesehen — veranstalte oder schau einem Sit & Go zu!",
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
  ["Tier 1 checks deck integrity, but it does not hide the deck from modified participant clients. Play with people you trust."] =
    "Tier 1 prüft die Integrität des Decks, verbirgt es aber nicht vor veränderten Spieler-Clients. Spielt mit Leuten, denen ihr vertraut.",
  ["fair play: hand verified"] = "Fair Play: Hand verifiziert",
  ["fair play: cards verified"] = "Fair Play: Karten verifiziert",
  ["fair play: deck sealed, verifying…"] = "Fair Play: Deck versiegelt, prüfe…",
  ["fair play: preparing…"] = "Fair Play: Vorbereitung…",
  ["fair play: FAILED"] = "Fair Play: FEHLGESCHLAGEN",
  ["fair play: couldn't verify this hand (missed a broadcast)"] = "Fair Play: Hand nicht prüfbar (Übertragung verpasst)",
  ["Hands fully verified this session: %d"] = "Vollständig geprüfte Hände diese Sitzung: %d",
  ["Participant checks are reported here only when they fail."] = "Prüfungen der Mitspieler werden hier nur gemeldet, wenn sie fehlschlagen.",
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
  ["Game on — dealing the first hand!"] = "Auf geht's — die erste Hand wird gegeben!",
  ["Sitting down at %s's table."] = "Du setzt dich an %ss Tisch.",
  ["Stood up from the table."] = "Du bist vom Tisch aufgestanden.",
  ["Table paused — break time! (Turn clock stopped; the current hand can be finished at leisure.)"] = "Tisch pausiert — Pause! (Die Uhr steht; die laufende Hand kann in Ruhe zu Ende gespielt werden.)",
  ["Break over — the clock is back on and dealing continues."] = "Pause vorbei — die Uhr läuft wieder und es wird weiter gegeben.",
  ["Sitting out — you keep your seat and chips; hands skip you until you return."] = "Du setzt aus — Platz und Chips bleiben dir; Hände überspringen dich, bis du zurückkehrst.",
  ["You're back in — dealt from the next hand."] = "Du bist zurück — ab der nächsten Hand wird dir gegeben.",
  ["Guild leaderboard cleared."] = "Gilden-Rangliste geleert.",
  ["Watching %s's table — the cards are checked as you watch."] = "Du schaust %ss Tisch zu — die Karten werden live geprüft.",
  ["Stopped watching."] = "Zusehen beendet.",
  ["loaded — type /azh to open the casino."] = "geladen — tippe /azh, um das Casino zu öffnen.",
  ["Achievement unlocked: %s"] = "Erfolg freigeschaltet: %s",
  ["Blinds up! Level %s: %s/%s"] = "Blinds steigen! Stufe %s: %s/%s",
  ["%s finishes %s."] = "%s belegt Platz %s.",
  ["%s wins the Sit & Go!"] = "%s gewinnt das Sit & Go!",
}

DICT.ruRU = {
  -- achievements (names kept evocative; descriptions exact)
  ["First Blood"] = "Первая кровь", ["Win your first hand"] = "Выиграйте первую руку",
  ["On a Roll"] = "На ходу", ["Win 10 hands"] = "Выиграйте 10 рук",
  ["Card Shark"] = "Карточная акула", ["Win 100 hands"] = "Выиграйте 100 рук",
  ["Table Regular"] = "Завсегдатай", ["Play 100 hands"] = "Сыграйте 100 рук",
  ["The Grinder"] = "Гриндер", ["Play 1,000 hands"] = "Сыграйте 1 000 рук",
  ["Heater"] = "Кураж", ["Win 5 hands in a row"] = "Выиграйте 5 рук подряд",
  ["Monster Pot"] = "Огромный банк", ["Win 500+ chips in one hand"] = "Выиграйте 500+ фишек в одной руке",
  ["Boat Builder"] = "Строитель фулл-хауса", ["Make a Full House"] = "Соберите фулл-хаус",
  ["Quad Damage"] = "Каре", ["Make Four of a Kind"] = "Соберите каре",
  ["Royal Line"] = "Королевский ряд", ["Make a Straight Flush"] = "Соберите стрит-флеш",
  ["All-In, All Win"] = "Олл-ин и победа", ["Win a hand after going all-in"] = "Выиграйте руку после олл-ина",
  ["Stone Cold Bluffer"] = "Хладнокровный блефёр", ["Win 25 hands without a showdown"] = "Выиграйте 25 рук без вскрытия",
  ["Closer"] = "Финишёр", ["Win a Sit & Go"] = "Выиграйте Sit & Go",
  ["Dynasty"] = "Династия", ["Win 3 Sit & Gos"] = "Выиграйте 3 Sit & Go",
  ["House Dealer"] = "Дилер заведения", ["Deal 50 hands as the host"] = "Раздайте 50 рук в роли хоста",
  ["Trust, but Verify"] = "Доверяй, но проверяй", ["100 hands verified clean"] = "100 рук проверено начисто",
  -- leaderboard
  ["Guild Leaderboard"] = "Таблица гильдии",
  ["Sit & Go results seen on this floor."] = "Результаты Sit & Go, увиденные на этом этаже.",
  ["Player"] = "Игрок", ["Won"] = "Поб.", ["Cashed"] = "Призы", ["Played"] = "Сыгр.",
  ["Observed live — not a verified ranking. /azh top reset to clear."] = "Видно вживую — не проверенный рейтинг. /azh top reset для сброса.",
  ["No tournaments seen yet — host or watch a Sit & Go!"] = "Турниров пока не видно — проведите Sit & Go или посмотрите!",
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
  ["Tier 1 checks deck integrity, but it does not hide the deck from modified participant clients. Play with people you trust."] =
    "Уровень 1 проверяет целостность колоды, но не скрывает её от изменённых клиентов игроков. Играйте с теми, кому доверяете.",
  ["fair play: hand verified"] = "честная игра: раздача проверена",
  ["fair play: cards verified"] = "честная игра: карты проверены",
  ["fair play: deck sealed, verifying…"] = "честная игра: колода запечатана, проверка…",
  ["fair play: preparing…"] = "честная игра: подготовка…",
  ["fair play: FAILED"] = "честная игра: ПРОВАЛ",
  ["fair play: couldn't verify this hand (missed a broadcast)"] = "честная игра: раздачу не удалось проверить (пропущен пакет)",
  ["Hands fully verified this session: %d"] = "Полностью проверено раздач за сессию: %d",
  ["Participant checks are reported here only when they fail."] = "Проверки участников отображаются здесь только при сбое.",
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
  ["Game on — dealing the first hand!"] = "Игра началась — раздаём первую руку!",
  ["Sitting down at %s's table."] = "Вы садитесь за стол игрока %s.",
  ["Stood up from the table."] = "Вы встали из-за стола.",
  ["Table paused — break time! (Turn clock stopped; the current hand can be finished at leisure.)"] = "Стол на паузе — перерыв! (Таймер остановлен; текущую руку можно спокойно доиграть.)",
  ["Break over — the clock is back on and dealing continues."] = "Перерыв окончен — таймер снова идёт, раздача продолжается.",
  ["Sitting out — you keep your seat and chips; hands skip you until you return."] = "Вы пропускаете — место и фишки остаются за вами; руки идут без вас, пока не вернётесь.",
  ["You're back in — dealt from the next hand."] = "Вы вернулись — со следующей руки вам раздают.",
  ["Guild leaderboard cleared."] = "Таблица гильдии очищена.",
  ["Watching %s's table — the cards are checked as you watch."] = "Вы смотрите стол игрока %s — карты проверяются вживую.",
  ["Stopped watching."] = "Просмотр остановлен.",
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
