# TODO


Thamani Dawa is better at symbol generation, but its implementation is not a perfect drop-in:

- Its invalid-GTIN fallback pads the original string instead of refusing generation.
- It places AI 10 before dates, which is valid but unnecessarily requires a separator.
- Its raw decoder accepts empty variable fields and duplicate AIs.
- Its raw decoder does not validate the GTIN check digit.
- Parentheses within batch or serial values require proper encoder escaping.


GS1's own rule settles which is right. Per the GS1 General Specifications, the governing rule has two parts:
1. A variable-length AI's data field must be terminated by FNC1/GS (ASCII 29) unless it's the last element string in the symbol — the terminator is only skippable at the very end.
2. On ordering: "predefined [fixed] length element strings should be followed by non-predefined [variable] length element strings" (GS1 Application Identifiers guide (https://plainbarcode.com/guides/gs1-application-identifiers-guide/); corroborated in multiple GS1 technical references found via search, and consistent with barcodefaq.com's AIM/GS1 FNC1 explainer (https://www.barcodefaq.com/2d/qr-code/aim-gs1-fnc1/)).

That second point is exactly the design decision in question, and it's not a stylistic preference — it's a direct robustness consequence of rule 1. Group all the fixed-length AIs first, and the only place in the whole symbol that ever depends on the separator surviving is the single boundary where the first variable field begins. Every fixed field before that point is immune to separator loss, because its boundary is positional, not separator-defined.

thamani_dawa's order violates that convention, and it's not just a style nit — it actively creates the exact failure mode you're fighting. By putting 10 (variable) immediately before 11/17 (fixed), it forces every label that has a batch number to rely on a surviving separator just to read the dates at all. If that separator is lost in transit, the batch value swallows into what should be the date bytes — you get garbage like letters inside a 6-digit date field instead of a clean parse failure. That's a worse failure shape than medic's: in medic's order, the dates always parse correctly regardless of separator survival; the fragile boundary is isolated to batch↔serial, which is the minimum unavoidable risk given both are free text.