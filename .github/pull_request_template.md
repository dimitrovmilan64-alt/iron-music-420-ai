## Какво / What

<!-- Кратко описание на промяната. / Short description of the change. -->

## Тест план / Test plan

- [ ] `flutter analyze --no-fatal-infos` и `flutter test` минават (CI зелен) / pass (CI green)
- [ ] Тест на евтиния Android телефон: инсталиран APK от CI артефакта, приложението стартира, засегнатата функция работи / Phone test on the cheap Android handset: CI APK installed, app starts, the changed feature works
- [ ] Ако е засегнат „Хей Айрън“: включване → изтегляне на модела → разпознаване → изключване, без рестарти и забиване / If Hey Iron is touched: enable → model download → detection → disable, no restart loops or freezes

> ⚠️ Не merge-вай, докато телефонният тест не е отметнат. Merge-вай стекнатите PR-и към `main` един по един.
> Do not merge until the phone test is ticked. Merge stacked PRs into `main` one at a time.
