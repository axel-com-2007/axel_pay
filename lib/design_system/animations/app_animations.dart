// ============================================================
// KIT D'ANIMATIONS AXELPAY
// ============================================================
// Regroupe tous les effets réutilisables décrits dans le brief UX :
//  - AnimatedPressable    : feedback tactile (scale au clic)
//  - FadeSlideIn           : apparition en cascade (listes staggered)
//  - ShimmerBox / ShimmerCard : squelettes de chargement
//  - AnimatedCounter       : compteur numérique animé (count-up)
//  - ShakeWidget           : secousse (erreur de saisie)
//  - GlowPulse             : halo lumineux pulsant (statut urgent)
//  - MorphingPayButton     : bouton qui se transforme en loader puis
//                            en coche de validation
//  - SwipeToConfirm        : glisser pour valider un paiement
//  - ConfettiBurst         : pluie de confettis à la validation
//  - AxisSwitcher          : transition "shared axis" entre onglets
//  - LottieAssets / LottieLoader / EmptyStateLottie / LottieOneShot :
//                            intégration des illustrations Lottie
//                            fournies (assets/animations/*.json)
//
// La quasi-totalité de ce fichier est écrite avec uniquement le SDK
// Flutter (AnimationController, Tween, CustomPainter), sans dépendance
// externe. Seule la section Lottie ci-dessous requiert le package
// `lottie` — voir la note d'intégration en bas de fichier.
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../colors/app_colors.dart';
import '../spacing/app_spacing.dart';
import '../typography/app_typography.dart';

// ------------------------------------------------------------
// 0. Illustrations Lottie (assets/animations/*.json)
// ------------------------------------------------------------
/// Chemins des 8 animations fournies, déposées telles quelles dans
/// `assets/animations/` (renommées en snake_case pour éviter tout souci
/// d'espaces/virgules dans les chemins d'assets Flutter — voir le
/// mapping exact dans le README d'intégration).
class LottieAssets {
  LottieAssets._();
  static const String click = 'assets/animations/click.json';
  static const String database = 'assets/animations/database.json';
  static const String girlSayHi = 'assets/animations/girl_say_hi.json';
  static const String loadingTurq = 'assets/animations/loading_turq.json';
  static const String login = 'assets/animations/login.json';
  static const String maintenance = 'assets/animations/maintenance.json';
  static const String password = 'assets/animations/password.json';
  static const String search = 'assets/animations/search.json';
}

/// Loader de marque en boucle (`loading_turq.json`), à la place d'un
/// `CircularProgressIndicator` nu partout où un chargement complet
/// d'écran ou de section est en cours (splash d'authentification,
/// attente de confirmation de paiement, sous-sections sans squelette
/// Shimmer dédié).
class LottieLoader extends StatelessWidget {
  final double size;
  final String? label;

  const LottieLoader({super.key, this.size = 96, this.label});

  @override
  Widget build(BuildContext context) {
    final anim = Lottie.asset(
      LottieAssets.loadingTurq,
      width: size,
      height: size,
      repeat: true,
      // Le fichier fourni n'est pas nécessairement teinté en turquoise
      // de marque : on force la couleur pour rester cohérent avec
      // AppColors.primary quel que soit le rendu d'origine du JSON.
      delegates: LottieDelegates(
        values: [
          ValueDelegate.color(const ['**'], value: AppColors.primary),
        ],
      ),
      errorBuilder: (context, error, stack) =>
          const CircularProgressIndicator(color: AppColors.primary),
    );
    if (label == null) return Center(child: anim);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          anim,
          const SizedBox(height: 8),
          Text(label!, style: AppTextStyles.bodyMuted),
        ],
      ),
    );
  }
}

/// État vide générique : illustration Lottie (une seule lecture, pas de
/// boucle — une scène statique en fin d'animation reste plus lisible
/// dans une liste vide qu'un mouvement permanent) + titre + sous-titre
/// optionnel. Réutilisé par tous les écrans de liste (compteurs,
/// factures, transactions, délégations, contrats...) pour un traitement
/// visuel cohérent des états "rien à afficher".
class EmptyStateLottie extends StatelessWidget {
  final String asset;
  final String title;
  final String? subtitle;
  final double size;

  const EmptyStateLottie({
    super.key,
    required this.asset,
    required this.title,
    this.subtitle,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              asset,
              width: size,
              height: size,
              repeat: false,
              errorBuilder: (context, error, stack) =>
                  const Icon(Icons.inbox_outlined, size: 56, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Micro-interaction ponctuelle : joue [asset] une seule fois quand
/// [trigger] passe de `false` à `true` (ex: `click.json` à l'ouverture
/// d'un volet FAQ), puis reste sur son enfant normal. N'affiche
/// l'animation que pendant sa durée de lecture, jamais en continu.
class LottieOneShot extends StatefulWidget {
  final String asset;
  final bool trigger;
  final double size;

  const LottieOneShot({
    super.key,
    required this.asset,
    required this.trigger,
    this.size = 28,
  });

  @override
  State<LottieOneShot> createState() => _LottieOneShotState();
}

class _LottieOneShotState extends State<LottieOneShot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
    if (widget.trigger) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant LottieOneShot old) {
    super.didUpdateWidget(old);
    if (widget.trigger && !old.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Lottie.asset(
        widget.asset,
        controller: _c,
        onLoaded: (composition) => _c.duration = composition.duration,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}

// ------------------------------------------------------------
// 1. Feedback d'enfoncement (Spring/Scale Effect)
// ------------------------------------------------------------
/// Réduit légèrement son enfant au toucher (0.97x) avec une courbe
/// "ressort", comme demandé pour les cartes de compteur et boutons.
class AnimatedPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final BorderRadius? borderRadius;

  const AnimatedPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
    this.borderRadius,
  });

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable> {
  double _scale = 1;

  void _set(double s) {
    if (widget.onTap != null) setState(() => _scale = s);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(widget.scaleDown),
      onTapUp: (_) => _set(1),
      onTapCancel: () => _set(1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

// ------------------------------------------------------------
// 2. Révélation progressive du contenu (Staggered Animations)
// ------------------------------------------------------------
/// Fait apparaître son enfant en glissant de [offsetY] px vers le haut
/// tout en passant de l'opacité 0 à 1. Utiliser [index] pour décaler
/// chaque élément d'une liste de `baseDelay` (50 ms par défaut).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;
  final double offsetY;
  final Duration duration;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDelay = const Duration(milliseconds: 60),
    this.offsetY = 16,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    Future.delayed(widget.baseDelay * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: _curved.value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - _curved.value) * widget.offsetY),
            child: child,
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------
// 3. Chargement et squelettes de données (Shimmer)
// ------------------------------------------------------------
/// Bloc gris traversé par une vague brillante, en boucle.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dx = _c.value * 3 - 1.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(dx - 1, 0),
            end: Alignment(dx, 0),
            colors: const [Color(0xFFE7ECEF), Color(0xFFF6F8F9), Color(0xFFE7ECEF)],
          ).createShader(rect),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(color: const Color(0xFFE7ECEF), borderRadius: widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Squelette imitant une AppCard (titre + 2 lignes) pendant le
/// chargement — se fond ensuite vers le vrai contenu (voir
/// [FadeThroughContent]).
class ShimmerCard extends StatelessWidget {
  final double titleWidth;
  const ShimmerCard({super.key, this.titleWidth = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: titleWidth, height: 18),
          const SizedBox(height: 14),
          const ShimmerBox(height: 28),
          const SizedBox(height: 10),
          ShimmerBox(width: titleWidth * 1.4, height: 14),
        ],
      ),
    );
  }
}

/// Fondu du squelette Shimmer vers le vrai contenu une fois les
/// données arrivées (`AnimatedOpacity` / `AnimatedCrossFade`).
class FadeThroughContent extends StatelessWidget {
  final bool loading;
  final Widget skeleton;
  final Widget child;
  const FadeThroughContent({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 350),
      crossFadeState: loading ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: skeleton,
      secondChild: child,
    );
  }
}

// ------------------------------------------------------------
// 4. Compteurs numériques animés (Count-up)
// ------------------------------------------------------------
class AnimatedCounter extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num value)? formatter;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.formatter,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final display = formatter != null ? formatter!(v) : v.toStringAsFixed(0);
        return Text(display, style: style);
      },
    );
  }
}

// ------------------------------------------------------------
// 5. Effets d'états vides et erreurs (Shake)
// ------------------------------------------------------------
class ShakeController {
  _ShakeWidgetState? _state;
  void _attach(_ShakeWidgetState s) => _state = s;

  /// Déclenche la secousse (à appeler dans un `catch` d'erreur de saisie).
  void shake() => _state?._shake();
}

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final ShakeController? controller;
  const ShakeWidget({super.key, required this.child, this.controller});

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    widget.controller?._attach(this);
  }

  void _shake() => _c.forward(from: 0);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final dx = sin(t * pi * 6) * (1 - t) * 10;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

// ------------------------------------------------------------
// 6. Halo lumineux pulsant (statut urgent / actif)
// ------------------------------------------------------------
class GlowPulse extends StatefulWidget {
  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final bool enabled;

  const GlowPulse({
    super.key,
    required this.child,
    this.color = AppColors.danger,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.enabled = true,
  });

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (widget.enabled) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final blur = 6 + _c.value * 12;
        final opacity = 0.22 + _c.value * 0.3;
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(opacity), blurRadius: blur, spreadRadius: 1),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

// ------------------------------------------------------------
// 7. Bouton de paiement dynamique (Stateful Morphing Button)
// ------------------------------------------------------------
enum PayButtonState { idle, loading, success }

class MorphingPayButton extends StatelessWidget {
  final String label;
  final PayButtonState state;
  final VoidCallback? onPressed;

  const MorphingPayButton({
    super.key,
    required this.label,
    required this.state,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = state != PayButtonState.idle;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: isDone ? 56 : double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: state == PayButtonState.success ? AppColors.success : AppColors.primary,
          borderRadius: BorderRadius.circular(isDone ? 28 : AppRadius.field),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isDone ? 28 : AppRadius.field),
            onTap: state == PayButtonState.idle ? onPressed : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: switch (state) {
                  PayButtonState.idle => Text(
                      label,
                      key: const ValueKey('idle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  PayButtonState.loading => const SizedBox(
                      key: ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    ),
                  PayButtonState.success => const Icon(
                      Icons.check_circle,
                      key: ValueKey('success'),
                      color: Colors.white,
                      size: 26,
                    ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// 8. Glissement pour payer / valider (Swipe-to-Action)
// ------------------------------------------------------------
class SwipeToConfirm extends StatefulWidget {
  final String label;
  final String confirmingLabel;
  final Future<void> Function() onConfirm;
  final Color color;

  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.confirmingLabel = 'Validation…',
    this.color = AppColors.primary,
  });

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> {
  double _drag = 0;
  bool _locked = false;
  static const double _thumbSize = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = max(0.0, constraints.maxWidth - _thumbSize - 8);
        final progress = maxDrag == 0 ? 0.0 : (_drag / maxDrag).clamp(0, 1).toDouble();
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: widget.color.withOpacity(0.28)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Remplissage progressif turquoise derrière le curseur
              AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: _drag + _thumbSize,
                height: 56,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              Center(
                child: AnimatedOpacity(
                  opacity: 1 - progress,
                  duration: const Duration(milliseconds: 120),
                  child: Text(
                    _locked ? widget.confirmingLabel : widget.label,
                    style: TextStyle(color: widget.color, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _locked ? const Duration(milliseconds: 220) : Duration.zero,
                curve: Curves.easeOut,
                left: 4 + _drag,
                child: GestureDetector(
                  onHorizontalDragUpdate: _locked
                      ? null
                      : (details) => setState(() {
                            _drag = (_drag + details.delta.dx).clamp(0, maxDrag);
                          }),
                  onHorizontalDragEnd: _locked
                      ? null
                      : (details) async {
                          if (_drag > maxDrag * 0.7) {
                            setState(() {
                              _locked = true;
                              _drag = maxDrag;
                            });
                            await widget.onConfirm();
                          } else {
                            setState(() => _drag = 0);
                          }
                        },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: widget.color.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: _locked
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------
// 9. Confettis / Célébration au paiement
// ------------------------------------------------------------
class ConfettiBurst extends StatefulWidget {
  final bool play;
  const ConfettiBurst({super.key, required this.play});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final List<_Particle> _particles = [];
  final _rand = Random();

  static const _colors = [
    AppColors.primary,
    AppColors.secondaryGreen,
    AppColors.success,
    AppColors.secondary,
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    if (widget.play) _start();
  }

  @override
  void didUpdateWidget(covariant ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) _start();
  }

  void _start() {
    _particles
      ..clear()
      ..addAll(List.generate(46, (_) => _Particle(_rand)));
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_particles, _c.value, _colors),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  final double x;
  final double vy;
  final double vx;
  final double rotSpeed;
  final int colorIndex;
  _Particle(Random r)
      : x = r.nextDouble(),
        vy = 0.55 + r.nextDouble() * 0.55,
        vx = (r.nextDouble() - 0.5) * 0.5,
        rotSpeed = (r.nextDouble() - 0.5) * 12,
        colorIndex = r.nextInt(4);
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final List<Color> colors;
  _ConfettiPainter(this.particles, this.t, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    for (var i = 0; i < particles.length; i++) {
      final p = particles[i];
      final dy = p.vy * t * size.height;
      final dx = p.vx * t * size.width;
      final opacity = (1 - t).clamp(0, 1).toDouble();
      final paint = Paint()..color = colors[p.colorIndex].withOpacity(opacity);
      final cx = (p.x * size.width + dx).clamp(0.0, size.width);
      canvas.save();
      canvas.translate(cx, dy);
      canvas.rotate(p.rotSpeed * t * pi);
      canvas.drawRect(const Rect.fromLTWH(-4, -6, 8, 12), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}

// ------------------------------------------------------------
// 10. Transitions d'axes contigus entre onglets (Shared Axis)
// ------------------------------------------------------------
/// À utiliser autour du contenu qui change selon l'onglet actif
/// (ex : `AxisSwitcher(index: currentIndex, children: _screens)`),
/// pour un glissement + fondu doux façon "shared axis" du package
/// `animations`, sans dépendance externe.
class AxisSwitcher extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const AxisSwitcher({super.key, required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(index),
        child: children[index],
      ),
    );
  }
}
