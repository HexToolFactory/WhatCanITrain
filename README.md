# What Can I Train

A World of Warcraft: Forever addon that shows what your class, weapon, pet and profession trainers can teach you,
what it costs, and what comes next - with a shopping list and a **Buy All** button at the trainer.

## Features
- **Spellbook tab** (book icon next to the spellbook's category tabs) with your class, weapon and pet training.
- **Profession window button** (top right) with the training list of the open profession.
- Groups: Available Now, Available but Missing Requirements, Coming Soon, Not Yet Available, Not Buying Now, Already Known - each with its total cost.
- **Read from the game:** the lists come from the trainer window the first time you visit a trainer. Nothing is hard-coded, so the data always matches the client.
- **Shopping list:** uncheck a skill you will not buy now. It moves to "Not Buying Now" and is left out of all totals.
  **Ctrl+click** a checkbox or a row to check or uncheck every rank of that spell at once.
- **Buy All** in the trainer window learns every checked skill you can learn and afford right now.
  Higher ranks unlock once the lower rank is learned - click again then. New professions are never bought by it.
- Shift+click a row to link the spell in chat; right-click for the rank menu.
- LibDataBroker launcher with a summary tooltip.

## Commands
- `/wcit` - open the list (it appears the next time you open the spellbook)
- `/wcit status` - show what has been recorded
- `/wcit unignore` - check every skill of this character again
- `/wcit reset` - forget all recorded trainer data

## Credits
Modelled on [What's Training?](https://www.curseforge.com/wow/addons/whats-training) by Fusionpit / Sveng (MIT).
This addon is a separate implementation for WoW: Forever that reads the trainer window instead of shipping spell data.

## License
MIT - see [LICENSE](LICENSE).
