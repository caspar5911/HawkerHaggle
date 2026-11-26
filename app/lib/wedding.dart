import 'package:flutter/material.dart';

import 'widgets.dart';

class WeddingCard extends StatelessWidget {
  const WeddingCard({super.key, required this.event, required this.onChoose, required this.onVisit});

  final Map event;
  final ValueChanged<String> onChoose;
  final VoidCallback onVisit;

  @override
  Widget build(BuildContext context) {
    final stage = event['stage'] as int;
    final role = event['choice'];
    final ready = event['ready'] == true;
    final (title, description) = switch (stage) {
      1 => (
        'A wedding at the market',
        ready
            ? 'The mangoes are packed. Now help Auntie Mei get a two-star deal on Uncle Lim’s prawns.'
            : 'The mangoes are packed in red paper. Get to know Auntie Mei better to help with the dinner.',
      ),
      2 => (
        'The wedding table is set!',
        switch (role) {
          'table' => 'Auntie Mei is keeping you a seat.',
          'stall' => 'You offered to watch the fruit stall so Auntie Mei can celebrate.',
          _ => 'Your prawn deal saved the dinner. Auntie Mei waves you over.',
        },
      ),
      _ => (
        'A photo for the market',
        switch (role) {
          'table' => 'Auntie Mei framed the photo from your table at the wedding.',
          'stall' => 'Auntie Mei framed the photo with a thank-you for looking after her stall.',
          _ => 'Auntie Mei framed a wedding photo to remember everyone who helped.',
        },
      ),
    };
    return Container(
      key: const ValueKey('wedding_card'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1DE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAB575)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WeddingKeepsake(event: event),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(color: Palette.ink)),
          if (stage == 2 && role == null)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: () => onChoose('table'), child: const Text('Join the table')),
                OutlinedButton(onPressed: () => onChoose('stall'), child: const Text('Mind her stall')),
              ],
            ),
          if (stage < 3)
            TextButton(onPressed: onVisit, child: Text(stage == 1 && ready ? 'Visit Uncle Lim' : 'Visit Auntie Mei')),
          if (stage == 2)
            Text(
              ready
                  ? 'Close a deal with Auntie Mei to finish the story.'
                  : 'Grow your friendship to open the last chapter.',
              style: const TextStyle(color: Palette.soft),
            ),
        ],
      ),
    );
  }
}

class WeddingTrim extends StatelessWidget {
  const WeddingTrim({super.key, required this.event});

  final Map event;

  @override
  Widget build(BuildContext context) {
    final text = switch ((event['stage'], event['choice'])) {
      (1, _) => 'Mangoes wrapped for the tea ceremony',
      (2, 'table') => 'A seat saved for you',
      (2, 'stall') => 'A sign on the counter: “Back after the wedding”',
      (2, _) => 'The wedding table is ready',
      (3, 'stall') => 'Wedding photo · “Thanks for minding the stall!”',
      _ => 'The wedding photo',
    };
    return Row(
      key: const ValueKey('wedding_trim'),
      children: [
        WeddingKeepsake(event: event),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Palette.ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class WeddingKeepsake extends StatelessWidget {
  const WeddingKeepsake({super.key, required this.event});

  final Map event;

  @override
  Widget build(BuildContext context) {
    final (emoji, label) = switch ((event['stage'], event['choice'])) {
      (1, _) => ('🥭', 'Wedding mangoes'),
      (2, 'stall') => ('🏮', 'Lantern at the fruit stall'),
      (2, _) => ('🍽️', 'Wedding table'),
      (3, 'stall') => ('👰🤵', 'Wedding photo with a thank-you card'),
      _ => ('👰🤵', 'Framed wedding photo'),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        width: 48,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: event['stage'] == 1 ? const Color(0xFFF4B0A4) : const Color(0xFFFCE3AC),
          border: Border.all(color: const Color(0xFFAB283B), width: 2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: event['stage'] == 3
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  if (event['choice'] == 'stall')
                    const Positioned(right: 0, bottom: 0, child: Text('💌', style: TextStyle(fontSize: 11))),
                ],
              )
            : Text(emoji, style: const TextStyle(fontSize: 23)),
      ),
    );
  }
}
