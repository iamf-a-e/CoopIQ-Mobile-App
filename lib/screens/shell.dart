import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/settings.dart';
import 'agrovet_screen.dart';
import 'chat_screen.dart';
import 'diagnose_screen.dart';
import 'flock_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(index: s.tab, children: const [
            HomeScreen(),
            DiagnoseScreen(),
            FlockScreen(),
            AgrovetScreen(),
            ProfileScreen(),
          ]),
        ),
        // The Ask bubble floats over Home, Diagnose and Flock. It is hidden on the
        // Vet forms and Profile so it never covers a button.
        floatingActionButton: s.tab <= 2 ? _AskBubble(onTap: () => openChat(context)) : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: s.tab,
          onDestinationSelected: s.go,
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: context.tr('nav_home')),
            NavigationDestination(
                icon: const Icon(Icons.center_focus_strong_outlined),
                selectedIcon: const Icon(Icons.center_focus_strong),
                label: context.tr('nav_diagnose')),
            NavigationDestination(
                icon: const Icon(Icons.event_note_outlined),
                selectedIcon: const Icon(Icons.event_note),
                label: context.tr('nav_flock')),
            NavigationDestination(
                icon: const Icon(Icons.medical_services_outlined),
                selectedIcon: const Icon(Icons.medical_services),
                label: context.tr('nav_agrovet')),
            NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: context.tr('nav_profile')),
          ],
        ),
      ),
    );
  }
}

class _AskBubble extends StatelessWidget {
  final VoidCallback onTap;
  const _AskBubble({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = Theme.of(context).scaffoldBackgroundColor;
    return Tooltip(
      message: context.tr('ask_coopiq'),
      child: SizedBox(
        width: 62,
        height: 62,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Material(
              color: scheme.primary,
              elevation: 5,
              clipBehavior: Clip.antiAlias,
              shape: CircleBorder(side: BorderSide(color: ring, width: 3)),
              child: InkWell(
                onTap: onTap,
                child: const Center(child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 27)),
              ),
            ),
          ),
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFF3F8F5B),
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
