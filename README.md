# Brick

Brick is a little brick person who lives on your screen and talks with you.
He stands in the bottom right corner, blinks, and waves when he talks.
Your mouse goes straight through him.

## Start him

```
./build.sh
open Brick.app
```

A little 🧱 shows up in the menu bar at the top. Click it and pick **Talk to Brick…**,
type something, and Brick answers. Pick **Quit Brick** to stop him.

## His brain (for a grown-up)

Brick's answers come from Claude, so he needs an Anthropic API key. Run this once:

```
./set-key.sh
```

It stores the key in the login Keychain, in the same spot the Claude mod uses, so if
that one is already set up Brick works with no extra steps. The key is never written to
this repo.

What is typed to Brick is sent to Anthropic to make his answer. Brick keeps the last
few lines in memory so he can follow the chat, and forgets everything when he quits.
He is told to be short and kind, and to say "ask a grown-up" about private things.

Made by Elduin. Mac only.
