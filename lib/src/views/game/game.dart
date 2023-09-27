import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restoria/src/objects/map/map.dart';
import 'package:restoria/src/objects/playerHero/player_hero.dart';
import 'package:restoria/src/objects/playerHero/player_hero_interface.dart';
import 'package:restoria/src/objects/util/interface/bars/HP/bars_ui.dart';
import 'package:restoria/src/objects/util/interface/menus/hero_menu_ui.dart';
import 'package:restoria/src/objects/util/interface/screens/game_menu.dart';
import 'package:restoria/src/objects/util/interface/screens/game_over.dart';
import 'package:restoria/src/objects/util/interface/screens/level_completed.dart';
import 'package:restoria/src/objects/util/providers/bgm_manager.dart';
import 'package:restoria/src/objects/util/providers/respawn_manager.dart';

import '../../objects/playerHero/player_hero_controller.dart';

class Game extends StatefulWidget {
  final int level;
  const Game({this.level = 1, Key? key}) : super(key: key);

  @override
  State<Game> createState() => _GameState();
}

class _GameState extends State<Game> with GameListener {
  final GameController _controller = GameController();
  late final PlayerHeroController heroController;
  late int _level;
  late int _gameHash;

  @override
  void initState() {
    heroController = BonfireInjector().get<PlayerHeroController>();
    _level = widget.level;
    _controller.addListener(this);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    SoundEffects.startBgm(BgmType.game);

    Vector2 mouseVector = Vector2(0, 0);
    FocusNode gameFocus = FocusNode();

    updateMouseCoords(PointerEvent details) {
      final x = details.position.dx;
      final y = details.position.dy;
      mouseVector = Vector2(x, y);
    }

    Vector2 getMouseVector() => mouseVector;

    return Material(
      child: LayoutBuilder(
        builder: (context, constraints) {
          MainMap.tileSize =
              math.max(constraints.maxHeight, constraints.maxWidth) / (kIsWeb ? 25 : 22);

          return MouseRegion(
            onHover: updateMouseCoords,
            child: Focus(
              onFocusChange: (_) => gameFocus.requestFocus(),
              child: BonfireWidget(
                gameController: _controller,
                showCollisionArea: true, // DebugMode
                focusNode: gameFocus,
                joystick: kIsWeb
                    ? Joystick(
                        keyboardConfig: KeyboardConfig(
                          keyboardDirectionalType: KeyboardDirectionalType.wasd,
                          acceptedKeys: [
                            LogicalKeyboardKey.space,
                            LogicalKeyboardKey.escape,
                            LogicalKeyboardKey.tab,
                            LogicalKeyboardKey.keyQ,
                            LogicalKeyboardKey.keyE,
                            LogicalKeyboardKey.keyR,
                          ],
                        ),
                      )
                    : Platform.isAndroid && Platform.isIOS
                        ? Joystick(
                            directional: JoystickDirectional(
                              spriteBackgroundDirectional: Sprite.load(
                                'joystick/joystick_background.png',
                              ),
                              spriteKnobDirectional: Sprite.load('joystick/joystick_knob.png'),
                              size: 100,
                              isFixed: false,
                            ),
                            actions: [
                              JoystickAction(
                                actionId: HeroAttackType.attackMelee,
                                sprite: Sprite.load('joystick/joystick_attack.png'),
                                align: JoystickActionAlign.BOTTOM_RIGHT,
                                size: 80,
                                margin: const EdgeInsets.only(bottom: 50, right: 50),
                              ),
                              JoystickAction(
                                actionId: HeroAttackType.attackRanged,
                                sprite: Sprite.load('joystick/joystick_attack_range.png'),
                                spriteBackgroundDirection: Sprite.load(
                                  'joystick/joystick_background.png',
                                ),
                                enableDirection: true,
                                size: 50,
                                margin: const EdgeInsets.only(bottom: 50, right: 160),
                              )
                            ],
                          )
                        : Joystick(
                            keyboardConfig: KeyboardConfig(
                              keyboardDirectionalType: KeyboardDirectionalType.wasd,
                              acceptedKeys: [
                                LogicalKeyboardKey.space,
                                LogicalKeyboardKey.escape,
                                LogicalKeyboardKey.tab,
                                LogicalKeyboardKey.keyQ,
                                LogicalKeyboardKey.keyE,
                                LogicalKeyboardKey.keyR,
                              ],
                            ),
                          ),
                player: PlayerHero(
                    Vector2((8 * MainMap.tileSize), (5 * MainMap.tileSize)), getMouseVector),
                interface: PlayerHeroInterface(),
                map: WorldMapByTiled(
                  'tile/map.json',
                  forceTileSize: Vector2(MainMap.tileSize, MainMap.tileSize),
                  objectsBuilder: {
                    // 'Goblin': (properties) => Goblin(properties.position),
                  },
                ),
                overlayBuilderMap: {
                  'Bars': (context, game) => const Bars(),
                  'GameOver': (context, game) => const GameOver(),
                  'GameMenu': (context, game) => GameMenu(game),
                  'MiniMap': (context, game) => MiniMap(
                        game: game,
                        margin: const EdgeInsets.all(10),
                        borderRadius: BorderRadius.circular(10),
                        size: Vector2.all(
                          math.min(constraints.maxHeight, constraints.maxWidth) / 7,
                        ),
                        border: Border.all(color: Colors.white.withOpacity(0.5)),
                      ),
                  'HeroMenu': (context, game) => HeroMenu(heroController: heroController),
                  'LevelCompleted': (context, game) => LevelCompleted(_level),
                },
                initialActiveOverlays: const [
                  'Bars',
                  'MiniMap',
                  'HeroMenu',
                ],
                cameraConfig: CameraConfig(
                  smoothCameraEnabled: true,
                  smoothCameraSpeed: 2,
                ),
                onReady: (BonfireGame game) async => await _onGameStart(game, _controller, _level),
                onDispose: () async => await _onGameOver(),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void changeCountLiveEnemies(int count) {
    log('changeCountLiveEnemies $count');
    if (count == 0) {
      _onLevelCompleted();
    }
  }

  @override
  void updateGame() {}

  Future _onGameStart(BonfireGame game, GameController controller, int level) async {
    _gameHash = game.gameController!.gameRef.hashCode;
    game.add(FpsTextComponent(position: Vector2(0, game.size.y - 24)));

    log('---------------------------------------------------------');
    log('_onGameStart: $_gameHash');
    log('---------------------------------------------------------');

    log('Creating RespawnManager for game: $_gameHash');
    RespawnManager.game = game;
    _onLevelStart();
  }

  void _onLevelStart() {
    log('Level $_level Started!');
    RespawnManager.spawnEnemiesForLevel(_level);
  }

  void _onLevelCompleted() {
    _controller.gameRef.overlayManager.add('LevelCompleted');
    log('Level $_level Cleared!');

    _level++;
  }

  _onGameOver() async {
    log('_onGameOver');
  }
}
