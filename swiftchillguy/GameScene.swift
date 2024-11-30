import SpriteKit
import GameplayKit
import AVFoundation  // Add this import

class GameScene: SKScene {
    // Physics Categories
    struct PhysicsCategory {
        static let bird: UInt32 = 0x1 << 0
        static let pipe: UInt32 = 0x1 << 1
        static let score: UInt32 = 0x1 << 2
    }
    
    enum GameState {
        case waitingToStart
        case playing
        case gameOver
    }
    
    // Game properties
    private var bird: SKSpriteNode!
    private var backgroundNode: SKSpriteNode!
    
    private let maxVelocity: CGFloat = 400.0
    private let impulseForce: CGFloat = 200.0
    
    private var gameState: GameState = .waitingToStart
    private var gameOverNode: SKSpriteNode?
    private var startLabel: SKLabelNode?
    
    private let maxRotation: CGFloat = .pi / 4    // 45 degrees
    private let minRotation: CGFloat = -.pi / 2   // -90 degrees
    private let rotationSpeed: CGFloat = 0.3
    
    // Add new properties at the top
    private let pipeGap: CGFloat = 120
    private let pipeSpeed: CGFloat = 147
    private let pipeSpawnInterval: TimeInterval = 1.35
    private var lastUpdateTime: TimeInterval = 0
    private var timeSinceLastSpawn: TimeInterval = 0
    private var pipes: [SKSpriteNode] = []
    
    // Add new properties
    private var scoreLabel: SKLabelNode!
    private var score: Int = 0 {
        didSet {
            updateScore()
        }
    }
    
    // Add new property at the top with other properties
    private var highScore: Int {
        get { UserDefaults.standard.integer(forKey: "HighScore") }
    }
    
    // Add new property for audio player
    private var backgroundMusic: AVAudioPlayer?
    
    override func didMove(to view: SKView) {
        setupBackgroundMusic()
        // Setup physics world
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8*1.1)
        physicsWorld.contactDelegate = self
        
        // Setup background
        setupBackground()
        setupBird()
        setupStartScreen()
        resetBird()
        setupScore()
    }
    
    private func setupBackground() {
        backgroundNode = SKSpriteNode(imageNamed: "background")
        backgroundNode.position = CGPoint(x: frame.midX, y: frame.midY)
        backgroundNode.zPosition = -1
        backgroundNode.size = frame.size
        addChild(backgroundNode)
    }
    
    private func setupBird() {
        bird = SKSpriteNode(imageNamed: "chillguy")
        bird.position = CGPoint(x: frame.midX/2, y: frame.midY)
        bird.size = CGSize(width: 50, height: 50)
        
        // Reduced collision radius from width/2 to width/2.5
        bird.physicsBody = SKPhysicsBody(circleOfRadius: bird.size.width/2.5)
        bird.physicsBody?.categoryBitMask = PhysicsCategory.bird
        bird.physicsBody?.contactTestBitMask = PhysicsCategory.pipe | PhysicsCategory.score
        bird.physicsBody?.collisionBitMask = PhysicsCategory.pipe
        bird.physicsBody?.isDynamic = true
        bird.physicsBody?.allowsRotation = false
        bird.physicsBody?.mass = 0.15
        bird.physicsBody?.linearDamping = 1.1
        bird.physicsBody?.restitution = 0.0
        
        addChild(bird)
    }
    
    private func setupStartScreen() {
        let attributedText = NSAttributedString(
            string: "Touch Screen to Start",
            attributes: [
                .strokeWidth: -4.0,
                .strokeColor: UIColor.black,
                .foregroundColor: UIColor.white,
                .font: UIFont(name: "Arial-Bold", size: 30) ?? UIFont.systemFont(ofSize: 40)
            ]
        )
        
        startLabel = SKLabelNode()
        startLabel?.attributedText = attributedText
        startLabel?.position = CGPoint(x: frame.midX, y: frame.midY)
        startLabel?.zPosition = 1
        if let startLabel = startLabel {
            addChild(startLabel)
        }
        
        bird.physicsBody?.isDynamic = false
    }
    
    private func resetBird() {
        bird.position = CGPoint(x: frame.midX/2, y: frame.midY)
        bird.physicsBody?.velocity = .zero
        bird.zRotation = 0  // Reset rotation when resetting bird
    }
    
    private func startGame() {
        gameState = .playing
        bird.physicsBody?.isDynamic = true
        startLabel?.removeFromParent()
        timeSinceLastSpawn = 0
        spawnPipe()
        score = 0
        scoreLabel.isHidden = false
        backgroundMusic?.play()
    }
    
    private func createPipePair() -> (top: SKSpriteNode, bottom: SKSpriteNode) {
        let pipeWidth: CGFloat = 80
        let minHeight: CGFloat = 100
        let maxHeight: CGFloat = frame.height - pipeGap - minHeight - 100
        let randomHeight = CGFloat.random(in: minHeight...maxHeight)
        
        // Create top pipe
        let topPipe = SKSpriteNode(imageNamed: "pipe")
        topPipe.zRotation = .pi
        topPipe.size = CGSize(width: pipeWidth, height: randomHeight)
        topPipe.position = CGPoint(x: frame.width + pipeWidth/2, y: frame.height - randomHeight/2)
        topPipe.physicsBody = SKPhysicsBody(rectangleOf: topPipe.size)
        topPipe.physicsBody?.isDynamic = false
        topPipe.physicsBody?.categoryBitMask = PhysicsCategory.pipe
        
        // Create bottom pipe
        let bottomPipe = SKSpriteNode(imageNamed: "pipe")
        bottomPipe.size = CGSize(width: pipeWidth, height: frame.height - randomHeight - pipeGap)
        bottomPipe.position = CGPoint(x: frame.width + pipeWidth/2, y: (frame.height - randomHeight - pipeGap)/2)
        bottomPipe.physicsBody = SKPhysicsBody(rectangleOf: bottomPipe.size)
        bottomPipe.physicsBody?.isDynamic = false
        bottomPipe.physicsBody?.categoryBitMask = PhysicsCategory.pipe
        
        // Calculate exact center point between pipes for score node
        let gapCenterY = frame.height - randomHeight - (pipeGap / 2)
        
        // Create score node
        let scoreNode = SKNode()
        scoreNode.name = "scoreNode"
        let scoreSize = CGSize(width: 2, height: pipeGap/2) // Half the gap height to prevent early collisions
        scoreNode.position = CGPoint(x: frame.width + pipeWidth/2, y: gapCenterY)
        
        scoreNode.physicsBody = SKPhysicsBody(rectangleOf: scoreSize)
        scoreNode.physicsBody?.isDynamic = false
        scoreNode.physicsBody?.affectedByGravity = false
        scoreNode.physicsBody?.categoryBitMask = PhysicsCategory.score
        scoreNode.physicsBody?.contactTestBitMask = PhysicsCategory.bird
        scoreNode.physicsBody?.collisionBitMask = 0
        
        addChild(scoreNode)
        
        // Use same movement action for score node
        let moveAction = SKAction.moveBy(x: -frame.width - 100, y: 0, duration: TimeInterval(frame.width/pipeSpeed))
        scoreNode.run(SKAction.sequence([moveAction, SKAction.removeFromParent()]))
        
        return (topPipe, bottomPipe)
    }
    
    private func spawnPipe() {
        // Only spawn if we're in playing state
        guard gameState == .playing else { return }
        
        let (topPipe, bottomPipe) = createPipePair()
        addChild(topPipe)
        addChild(bottomPipe)
        pipes.append(contentsOf: [topPipe, bottomPipe])
        
        let moveAction = SKAction.moveBy(x: -frame.width - 100, y: 0, duration: TimeInterval(frame.width/pipeSpeed))
        let removeAction = SKAction.removeFromParent()
        let sequence = SKAction.sequence([moveAction, removeAction])
        
        topPipe.run(sequence)
        bottomPipe.run(sequence) {
            self.pipes.removeAll { $0 == topPipe || $0 == bottomPipe }
        }
        
        // Schedule next spawn
        timeSinceLastSpawn = 0
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch gameState {
        case .waitingToStart:
            startGame()
            
        case .playing:
            // Reset vertical velocity and apply new impulse
            let currentVelocity = bird.physicsBody?.velocity.dy ?? 0
            if currentVelocity < maxVelocity {
                bird.physicsBody?.velocity.dy = 0
                bird.physicsBody?.applyImpulse(CGVector(dx: 0, dy: impulseForce))
            }
            
        case .gameOver:
            restart()
        }
    }
    
    private func gameOver() {
        gameState = .gameOver
        bird.physicsBody?.isDynamic = false
        
        startLabel?.removeFromParent()
        
        gameOverNode = SKSpriteNode(imageNamed: "gameover")
        gameOverNode?.position = CGPoint(x: frame.midX, y: frame.midY + 50) // Moved higher up
        gameOverNode?.zPosition = 1
        gameOverNode?.setScale(0.0)
        
        if let gameOverNode = gameOverNode {
            addChild(gameOverNode)
            
            let scaleAction = SKAction.scale(to: 1.0, duration: 0.3)
            scaleAction.timingMode = .easeOut
            
            let showRestartLabel = SKAction.run { [weak self] in
                self?.addRestartLabel()
            }
            
            gameOverNode.run(SKAction.sequence([scaleAction, showRestartLabel]))
        }
        
        scoreLabel.isHidden = true
        
        // Save high score
        let currentHighScore = UserDefaults.standard.integer(forKey: "HighScore")
        if score > currentHighScore {
            UserDefaults.standard.set(score, forKey: "HighScore")
        }
        
        backgroundMusic?.stop()
    }
    
    private func addRestartLabel() {
        let attributedText = NSAttributedString(
            string: "Touch Screen to Restart",
            attributes: [
                .strokeWidth: -4.0,
                .strokeColor: UIColor.black,
                .foregroundColor: UIColor.white,
                .font: UIFont(name: "Arial-Bold", size: 30) ?? UIFont.systemFont(ofSize: 35)
            ]
        )
        
        startLabel = SKLabelNode()
        startLabel?.attributedText = attributedText
        startLabel?.position = CGPoint(x: frame.midX, y: frame.midY - 400)
        startLabel?.zPosition = 1
        startLabel?.alpha = 0.0
        
        // Add final score label
        let finalScoreText = NSAttributedString(
            string: "Final Score: \(score)",
            attributes: [
                .strokeWidth: -4.0,
                .strokeColor: UIColor.black,
                .foregroundColor: UIColor.white,
                .font: UIFont(name: "Arial-Bold", size: 30) ?? UIFont.systemFont(ofSize: 30)
            ]
        )
        
        let finalScoreLabel = SKLabelNode()
        finalScoreLabel.attributedText = finalScoreText
        finalScoreLabel.position = CGPoint(x: frame.midX, y: frame.midY - -300)  // Position below restart label
        finalScoreLabel.zPosition = 1
        finalScoreLabel.alpha = 0.0
        addChild(finalScoreLabel)
        
        // Add high score label
        let highScoreText = NSAttributedString(
            string: "High Score: \(highScore)",
            attributes: [
                .strokeWidth: -4.0,
                .strokeColor: UIColor.black,
                .foregroundColor: UIColor.white,
                .font: UIFont(name: "Arial-Bold", size: 30) ?? UIFont.systemFont(ofSize: 45)
            ]
        )
        
        let highScoreLabel = SKLabelNode()
        highScoreLabel.attributedText = highScoreText
        highScoreLabel.position = CGPoint(x: frame.midX, y: frame.midY - 150) // 50 points below final score
        highScoreLabel.zPosition = 1
        highScoreLabel.alpha = 0.0
        addChild(highScoreLabel)
        
        if let startLabel = startLabel {
            addChild(startLabel)
            // Fade in all labels
            let fadeIn = SKAction.fadeIn(withDuration: 0.3)
            startLabel.run(fadeIn)
            finalScoreLabel.run(fadeIn)
            highScoreLabel.run(fadeIn)
        }
    }
    
    private func restart() {
        // Remove game over nodes
        gameOverNode?.removeFromParent()
        gameOverNode = nil
        
        // Remove all tap to restart labels but keep score label
        self.children.filter { 
            $0 is SKLabelNode && $0 != scoreLabel 
        }.forEach { $0.removeFromParent() }
        
        // Reset game state
        gameState = .waitingToStart
        setupStartScreen()
        resetBird()
        
        // Remove all pipes
        pipes.forEach { $0.removeFromParent() }
        pipes.removeAll()
        
        // Reset spawn timer
        lastUpdateTime = 0
        timeSinceLastSpawn = 0
        
        // Remove all score nodes
        self.enumerateChildNodes(withName: "scoreNode") { node, _ in
            node.removeFromParent()
        }
        
        // Reset and hide score
        score = 0
        scoreLabel.isHidden = true
        
        backgroundMusic?.play()
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard gameState == .playing else { return }
        // Limit bird's vertical velocity
        if let velocity = bird.physicsBody?.velocity.dy {
            if (velocity > maxVelocity) {
                bird.physicsBody?.velocity.dy = maxVelocity
            } else if (velocity < -maxVelocity) {
                bird.physicsBody?.velocity.dy = -maxVelocity
            }
        }
        
        // Update bird rotation based on velocity
        if let velocity = bird.physicsBody?.velocity.dy {
            let rotation = velocity * 0.001  // Convert velocity to radians
            let targetAngle = max(minRotation, min(maxRotation, rotation))
            
            // Smooth rotation
            let actionDuration = rotationSpeed
            let rotateAction = SKAction.rotate(toAngle: targetAngle, duration: actionDuration, shortestUnitArc: true)
            bird.run(rotateAction)
        }
        
        // Keep bird within screen bounds
        if bird.position.y > frame.height {
            bird.position.y = frame.height
            bird.physicsBody?.velocity.dy = 0
        }
        
        // Check if bird fell below screen
        if bird.position.y < -bird.size.height {
            gameOver()
        }
        
        // Spawn pipes
        if lastUpdateTime > 0 {
            timeSinceLastSpawn += currentTime - lastUpdateTime
            if timeSinceLastSpawn >= pipeSpawnInterval {
                spawnPipe()
                timeSinceLastSpawn = 0
            }
        }
        lastUpdateTime = currentTime
    }
    
    private func setupScore() {
        scoreLabel = SKLabelNode(text: "Score: 0")
        scoreLabel.fontName = "Arial-Bold"
        scoreLabel.fontSize = 30
        scoreLabel.position = CGPoint(x: frame.midX, y: frame.height - 100)
        scoreLabel.zPosition = 1
        
        let attributedText = NSAttributedString(
            string: "Score: 0",
            attributes: [
                .strokeWidth: -4.0,
                .strokeColor: UIColor.black,
                .foregroundColor: UIColor.white,
                .font: UIFont(name: "Arial-Bold", size: 30) ?? UIFont.systemFont(ofSize: 30)
            ]
        )
        scoreLabel.attributedText = attributedText
        addChild(scoreLabel)
        scoreLabel.isHidden = true
    }
    
    private func updateScore() {
        let attributedText = NSAttributedString(
            string: "Score: \(score)",
            attributes: [
                .strokeWidth: -4.0,
                .strokeColor: UIColor.black,
                .foregroundColor: UIColor.white,
                .font: UIFont(name: "Arial-Bold", size: 30) ?? UIFont.systemFont(ofSize: 30)
            ]
        )
        scoreLabel.attributedText = attributedText
    }
    
    private func setupBackgroundMusic() {
        guard let musicURL = Bundle.main.url(forResource: "backgroundmusic", withExtension: "mp3") else {
            print("Could not find music file")
            return
        }
        
        do {
            // Configure audio session with options that prevent the warning
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            backgroundMusic = try AVAudioPlayer(contentsOf: musicURL)
            backgroundMusic?.numberOfLoops = -1
            backgroundMusic?.volume = 0.2
            backgroundMusic?.prepareToPlay()
            backgroundMusic?.play()
        } catch {
            print("Audio error: \(error.localizedDescription)")
        }
    }
}

// MARK: - SKPhysicsContactDelegate
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        guard gameState == .playing else { return }
        
        let firstBody = contact.bodyA
        let secondBody = contact.bodyB
        
        if (firstBody.categoryBitMask == PhysicsCategory.score && secondBody.categoryBitMask == PhysicsCategory.bird) ||
           (firstBody.categoryBitMask == PhysicsCategory.bird && secondBody.categoryBitMask == PhysicsCategory.score) {
            // Increment score
            score += 10
            
            // Remove score node
            let scoreNode = (firstBody.categoryBitMask == PhysicsCategory.score) ? firstBody.node : secondBody.node
            scoreNode?.removeFromParent()
            
        } else if (firstBody.categoryBitMask == PhysicsCategory.pipe && secondBody.categoryBitMask == PhysicsCategory.bird) ||
                  (firstBody.categoryBitMask == PhysicsCategory.bird && secondBody.categoryBitMask == PhysicsCategory.pipe) {
            gameOver()
        }
    }
}
