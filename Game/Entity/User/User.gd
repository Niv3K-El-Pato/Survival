extends CharacterBody2D

class_name User

signal OnShoeFire(user: User, spawnPoint: Node2D);

enum PLAYER_STATE {
	CROUCHING,
	ATTACKING_FLOOR,
	ATTACKING_AIR,
	STANDING,
	MOVING,
	DEFENDING,
	FALLING,
}

enum DIRECTION {
	LEFT,
	RIGHT
}

const SPEED = 100.0
const JUMP_VELOCITY = -400.0
@export var isPuppet = false;
@onready var label = $Label;
@onready var Sprite = $Sprite;
@onready var animationTree: AnimationTree = $AnimationTree;
@onready var stateMachine = animationTree["parameters/playback"];

var playerState = PLAYER_STATE.STANDING;
var direction = DIRECTION.LEFT;

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: int = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	updateState();

func updateLabel(text: String):
	label.text = text;

func updateState():
	updateDirection();
	updateHurtCollision();
	$HurtBox.monitoring = (playerState != PLAYER_STATE.DEFENDING);

	match playerState:
		PLAYER_STATE.STANDING:
			stateMachine.travel("IDLE");
		PLAYER_STATE.ATTACKING_FLOOR:
			stateMachine.travel("Kick");
		PLAYER_STATE.ATTACKING_AIR:
			stateMachine.travel("AttackingDown");
		PLAYER_STATE.CROUCHING:
			stateMachine.travel("Croutch");
		PLAYER_STATE.MOVING:
			stateMachine.travel("Walk");
		PLAYER_STATE.DEFENDING:
			stateMachine.travel("Block");
		PLAYER_STATE.FALLING:
			stateMachine.travel("Falling");

func updateHurtCollision():
	if (playerState == PLAYER_STATE.CROUCHING):
		$HurtBox/HurtCollilsionStanding.disabled = true;
		$HurtBox/HurtCollisionCrouched.disabled = false;
	else:
		$HurtBox/HurtCollilsionStanding.disabled = false;
		$HurtBox/HurtCollisionCrouched.disabled = true;

func updateDirection():
	Sprite.flip_h = (direction != DIRECTION.RIGHT);
	if (direction == DIRECTION.RIGHT):
		$KickHitBox.transform.x = Vector2(1, 0);
		$MarkerContainer.transform.x = Vector2(1, 0);
	else:
		$KickHitBox.transform.x = Vector2(-1, 0);
		$MarkerContainer.transform.x = Vector2(-1, 0);

func _physics_process(delta: float) -> void:
	if (isPuppet):
		return;
	synchronizeData();

	# Handle Jump.
	var canMove = (
		playerState != PLAYER_STATE.ATTACKING_FLOOR &&
		playerState != PLAYER_STATE.CROUCHING
	);

	handleMovement(canMove);
	handleInput();

	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta
		if !Input.is_action_just_pressed("attack"):
			playerState = PLAYER_STATE.FALLING;

	move_and_slide();
	updateState();

func handleInput():
	if (playerState != PLAYER_STATE.ATTACKING_FLOOR):
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			stateMachine.travel("Jumping");
		if Input.is_action_just_pressed("attack"):
			if (is_on_floor()):
				playerState = PLAYER_STATE.ATTACKING_FLOOR;
			else:
				playerState = PLAYER_STATE.ATTACKING_AIR;
		if Input.is_action_pressed("defend"):
				playerState = PLAYER_STATE.DEFENDING;
		if Input.is_action_pressed("ui_down"):
			playerState = PLAYER_STATE.CROUCHING;
		if Input.is_action_just_pressed("fireShoe"):
			OnShoeFire.emit(self, $MarkerContainer/ShowSpawnerPosition);

func handleMovement(canMove: bool):
	var directionVector := Input.get_axis("ui_left", "ui_right")
	if directionVector and canMove:
		playerState = PLAYER_STATE.MOVING;
		velocity.x = directionVector * SPEED
		if (directionVector > 0):
			direction = DIRECTION.RIGHT;
		else:
			direction = DIRECTION.LEFT;
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		playerState = PLAYER_STATE.STANDING;

func synchronizeData():
	var data = {
		"name": Game.playerName,
		"playerState": playerState,
		"direction": direction,
		"position" : {
			"x": position.x,
			"y": position.y,
		},
	}

	if (Game.isHost()):
		data.playerType = Game.PLAYER_TYPE.HOST;
	else:
		data.playerType = Game.PLAYER_TYPE.CLIENT;

	WS.sendEvent("game-sync", data);

func _on_hurt_box_area_entered(area: Area2D) -> void:
	if (!isPuppet):
		return;

	if (!area.is_in_group('hit')):
		return;
	var parent = area.get_parent();
	if (parent is User && !parent.isPuppet):
		Game.win();