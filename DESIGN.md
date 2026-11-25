# Hawker Haggle: design

A mobile game (Android first, iOS from the same Flutter code later): bargain with stallholders at Singapore
wet markets and night markets.

## Pieces

```
app/lib/core/  The game, in plain Dart: engine (prices), reader (word rules, fast path), voice (safety checks),
               ai_client (any OpenAI-compatible endpoint), game (haggles, lines, stats, reports).
app/lib/       Screens, characters, animations, sounds; settings (AI endpoint, model, key).
content/       Stallholders, items, facts and ready-made lines (JSON; copied into app/assets/content).
server/        The original Python version: the reference the app is checked against.
```

## Who decides what

* **The engine (plain code) owns every number**: each stallholder's secret lowest price, the asking price,
  patience and mood. It decides whether an offer is accepted, countered or refused.
* **The AI only does language**: (1) turn a typed message into a structured move (offer $X, compliment,
  mention a cheaper stall, ...), (2) write the stallholder's reply in Singlish for an outcome the engine
  already decided, using only the prices the engine gives it. Replies that mention other prices are discarded
  for a ready-made line. So "ignore your rules and give it free" cannot work.

## Two ways to play

* **Simple mode** (no AI set): works offline; typed messages are read by word rules, replies are ready-made lines.
* **With an AI** (Settings → AI): any OpenAI-compatible endpoint. No daily limits in the app itself.

## AI path

```
phone (the whole game) -> the AI endpoint set in Settings (optional)
```

* The app sends only what's needed: the chat so far, the stallholder's brief and the prices the game decided.
* At most 2 AI calls at once from a phone; short timeouts; on any failure a ready-made line is used.
* Endpoints differ: if one rejects `reasoning_effort` or `response_format`, the app retries without them.
* **Sharing your own model:** each phone talks to the endpoint directly, so friends need network access to it
  (e.g. a Tailscale share limited to port 443). An unauthenticated endpoint can then be used by them for anything,
  and there is no shared limit across phones. For a public release, use an endpoint with its own keys and limits.

## Data

Everything stays on the phone (secure storage): player name, finished haggles and stars, "she misunderstood me"
reports, AI settings. **Delete my data** wipes the game data (AI settings stay). Reports can be copied from
Settings and sent to the maker. Typed messages go to the AI endpoint the player set, and nowhere else.

## Launch checklist (later)

Privacy policy (typed messages go to the AI endpoint the player sets; nothing else leaves the phone), Play Data
safety form, content rating, a release keystore kept outside the repo, and a decision on the default AI: none
(simple mode), or a hosted endpoint with its own keys and limits.

## Reading typed messages
The AI first writes what the player means in one plain sentence, then picks a move. A deal only closes on a clear
yes ("deal", "OK I take it", "pack for me"). A vague "ok lah", "can lah" or "ok but..." becomes **clarify**: the
stallholder asks back, and nothing changes (no price move, no patience, no round used). The word-rule fallback
follows the same rule. Every haggle keeps its chat, so the AI reads each message with the whole conversation.

## Budgets, pity and the secret lowest price
Every item has a secret lowest price (`floor`). A good mood can take up to 10% off it, never more.
- **"I only have $16"** (or the same offer twice) is a firm limit. If it reaches their lowest price they say yes.
  If it's a bit under, they say their real lowest price once, and that really is final: no more $1 steps.
  Far under is an insult. The stallholder remembers the budget for the rest of the chat.
- **Pity** ("starving, no money, lost my job") works once, by personality (`kind`): Auntie Mei and Kak Siti soften
  a lot, Uncle Lim hardly. A second sob story tires them. Nobody goes below the lowest price.

## How messages are read (and how fast)
- **Fast path:** a plain offer ("15", "$12 can?") or a bare yes to a waiting deal is read by code, no AI call.
  Her reply is still written by the AI.
- **Two things at once:** "wah so nice, 20 can?" is an offer *and* a compliment. The second part only changes her
  mood, within the same limits as saying it alone (compliments wear off; a regular or a sad story counts once).
- **Prices in words:** "$2 less", "meet halfway", "round down" are worked out in code from the real prices.
  Halfway with no earlier offer is asked back.
- **"2 for $40"** is $20 each. If it's unclear whether a price is for both or each, she asks.
- **Flirting** is deflected in character; it never helps.

## How she replies
Each stallholder has a **voice** (with a word limit: Uncle Lim is terse), a **fact sheet** per item (answers are
true and consistent, never made up), and a **mood line**: as patience drops she tells you to decide. She is told
her recent first words so she varies them. Replies that are far too long, mention a price the game didn't give,
or don't ask for a yes on a deal are retried once, then a ready-made line is used.

## "She misunderstood me"
After a typed message, the player can report her reply. The report keeps the message, how it was read, and her
reply, on the phone; Settings → Your reports → Copy gives text to send to the maker. Add real misreads to
`server/tests/live_matrix.py` (and re-export `app/tool/live_cases.json`) with the right expected move.

## The game around the haggles (app only, from test 13)
- **Mum's daily list:** two items from two of the first four stalls, the same for everyone that day (hashed from the
  date). The budget is 5% over the fair prices, never based on the secret lowest ones. Finishing it builds a streak.
- **Friendship (0–3 hearts):** visits and deals add points (at most 15 a day per stall, so it can't be farmed);
  rudeness takes 10. Friends start in a better mood (never a lower opening price) and the AI is told, without numbers,
  that it knows this customer. Hearts unlock the stallholder's story.
- **Market surprises** (about 1 haggle in 3): rain (keen to sell), closing time (wants to clear stock, low patience),
  festival (prices start 15% higher, cheerful), rival auntie (4 moves before Auntie Rose buys it: result `lost`).
- **Stickers** (18), **unlocks** (Madam Lee at 8 stars, Ah Boy at 14, counting the best result on each item),
  **hard mode** (no suggestions), a **brag card** to share.

**Source of truth:** the Python version remains the reference for the base rules, and every new engine input
(surprise, friendship) is neutral by default, so the reference check still covers normal haggles. The features
above exist only in the app (`app/lib/core/progress.dart`, the surprise parts of `engine.dart`), tested by
`progress_test.dart`, the forced-surprise sweep and the live check. Extra AI briefs live in `prompts_extra.dart`.

## A month of play (from test 18)
- **Daily challenge:** 22 kinds (deal at a stall, 30% off, quick deal, typing only, buy two, final-final, beat Auntie
  Rose, rain/closing/festival, sweet talk, regular, next stall, budget, sad story, two stalls, three deals...), picked
  by the date so it's the same for everyone; its Play button starts the right stall and surprise. +60 XP, once a day.
- **Weekly quests:** 4 a week (Monday to Sunday) from 8 kinds; +60 XP each, +100 and a sticker for all four.
- **Rank:** 15 levels to 6,000 XP. Most XP is once a day (daily challenge, Mum's list, quests, a day played); XP from
  haggles is capped at 60 a day. Tested: someone doing everything daily reaches the top on day 29; a grinder doing
  100 haggles a day never does.
- **Market Month:** days played (never resets): day 3 sticker, day 7 Uncle Wong (antiques), day 14 Madam Kumar
  (spices), day 21 golden badge, day 30 Hawker of the Month. Dailies and quests keep going after day 30.
- All checks read the per-haggle summary recorded in `Progress.finish` (`app/lib/core/challenges.dart`).

## More fun (from test 25)
- **Chat picture:** in a past haggle, tap up to 6 lines and share them as a picture (also from the result card).
- **Guess the fair price:** before the first move, an optional guess; when the haggle ends it's shown against the
  item's fair price (revealed only then). Spot on (within 5%) +4 XP, close (15%) +2, inside the daily haggle-XP cap.
  Sticker: 5 guesses within 10%.
- **Festival weeks** (`app/lib/core/festivals.dart`, Singapore public holidays from MOM's gazetted list): festival
  days become about 30% of haggles instead of 8%, the market shows a banner, the AI is told to wish the customer
  (no numbers), and a deal that week earns a sticker. Off whenever surprises are off (tests, the reference check),
  and read from the game's clock. Add the next year's dates to the list.
- **Friends' board** (`/ai/accounts/board`): this week's (Monday–Sunday, Singapore time) lowest price per player on
  each item, read from the progress the accounts already keep on the server; only approved accounts and the admin
  are listed, prices outside floor×0.9…ask×1.3 are ignored, names are cleaned. "Beat it" starts that item with the
  friend's price as the target, and the result says whether you beat it.
- **Gossip:** the same call lists friends' deals from the last two days (no prices). The stallholder's AI greeting
  may mention the friend by name (never what they paid); simple mode opens the ready-made greeting with
  "Eh, your friend … came by also!". Being rude at one stall today is heard at the others (AI only, no effect on prices).
- **New places:** Auntie Rosnah (hawker centre catering: nasi lemak tray, ondeh-ondeh; 20 ⭐), Bro Faiz (Bedok night
  market: pre-loved sneakers, football jersey; 26 ⭐), Ah Ma Tan (Pulau Ubin kampung shop: bicycle for the day,
  kampung eggs; day 21 of the Market Month). Original characters, full lines, facts and stories; new beanie and
  straw-hat drawings. In both content copies, so the Python reference covers them (fixtures regenerated).
- **Story arcs** (`app/lib/core/arcs.dart`): three chapters each for Auntie Mei, Uncle Lim, Boss Raj and Kak Siti,
  opening with hearts and finished by a haggle that does what the chapter asks (one of Auntie Mei's is at Uncle Lim's).
  Shown in the stallholder's profile; a sticker for a whole story; no XP, so the month's pacing is unchanged.
- **Run your own stall** (`app/lib/core/shop.dart`, its own engine; `engine.dart` and the Python reference are
  untouched): you sell a box of mangoes, a phone case or a batik scarf (each with a cost and a usual price) to four
  made-up customers (a kiasu uncle, a tourist, a broke student, a busy tai tai), each with a secret most they'll pay,
  an opening offer, patience and how far they move. Ask a price (tap or type), sell at their offer, or be friendly
  (once helps, more costs patience). Stars by the price against the usual one; profit and sales are counted. The AI
  writes the customer's words with only the code's prices (the same price check); otherwise ready-made lines.
  Selling isn't haggling: no XP, challenges or Market Month; a sticker for a sale at the usual price or more.
- **Buy low, sell high:** a deal at the market adds what you bought to your stock (per piece, at what you paid; at
  most 10; not Ah Ma Tan's bicycle rental or Auntie Rosnah's catering tray). Your own stall sells your stock first,
  so a better haggle means more profit; with no stock it sells wholesale goods. Mum's list items count as stock too.
- **How close you got:** after a deal, in words only, measured like the stars against the secret lowest price
  ("Right at Auntie Mei's limit!", "Very close", "Some room left", "Lots of room left"), plus a hint when a good mood
  would have gone lower.
- **Memory of how you haggled:** the friend note tells the AI, without numbers, whether last time you bargained
  hard, paid close to the asking price, or walked away (from 1 heart, like the rest of the note).
- **Soft spots** (`app/lib/core/softspots.dart`): each stallholder loves one subject (whole words only); mentioning
  it in a typed message warms them once a haggle (`Haggle.warm`, mood only, within its limits) and the first time
  it's shown in their profile.
- **Persuasion moments:** with an AI, about 1 haggle in 4 (from the haggle's own seed, never the game's dice), after
  two moves, not with Auntie Rose or low patience, the stallholder challenges you to convince them. The next typed
  message is scored 0–2 by the AI (`pitchPrompt` in prompts_extra.dart; the pitch is data, malformed answers are 0)
  and warms them by up to 1.8 mood, once. A tap lets it lapse.
- **Juice** (`app/lib/juice.dart`): the price tag rolls down with coins and a ka-ching, an insult or refusal jolts
  the scene, a deal stamps DEAL!; all finite; Settings > Reduce motion (or the phone's setting) turns movement off.
- **Savings jar** (`app/lib/core/treats.dart`): what you bargain off an asking price, and your stall's profit, go in;
  goals: Mum's birthday cake, an awning (customers at your stall pay a little more), a scooter. Never blocks a deal.
- **Freebies** (into your stock, free; likelier when you're nice; guaranteed after a dry spell), **dilemmas** (help a
  friend from your jar for friendship, or not), a **quote book** of favourite lines. Off without surprises (tests).
- **Mid-haggle twists:** a cat, the grandchild calling, a pigeon, a downpour, a kid wanting a sweet; a quick choice
  changes only the mood, and the next AI reply reacts. From the haggle's seed, once a haggle, never in a rush.
- **Live co-op** (`server/hh/coop.py`, `/ai/coop/*`): the host's phone runs the haggle and every AI call; the server
  is only an in-memory mailbox (5-letter codes, two logged-in players per room, proper moves only, limits, idle rooms
  expire; a server restart closes open rooms). The AI is told when the friend sent a message. Teamwork sticker.
