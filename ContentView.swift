import SwiftUI

// Extension to check for bullet-enemy collisions
extension CGSize {
    func intersects(with other: CGSize) -> Bool {
        let bulletFrame = CGRect(x: self.width - 5, y: self.height - 5, width: 10, height: 10)
        let enemyFrame = CGRect(x: other.width, y: other.height, width: 50, height: 50)
        return bulletFrame.intersects(enemyFrame)
    }
}

#if os(macOS)
import AppKit

let upArrow = "↑"
let downArrow = "↓"
let leftArrow = "←"
let rightArrow = "→"

struct KeyboardHandlingView: NSViewRepresentable {
    var onKeyPress: (NSEvent) -> Void
    var onKeyRelease: (NSEvent) -> Void

    class NSViewType: NSView {
        var onKeyPress: (NSEvent) -> Void
        var onKeyRelease: (NSEvent) -> Void

        init(onKeyPress: @escaping (NSEvent) -> Void, onKeyRelease: @escaping (NSEvent) -> Void) {
            self.onKeyPress = onKeyPress
            self.onKeyRelease = onKeyRelease
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func keyDown(with event: NSEvent) {
            onKeyPress(event)
        }
        override func keyUp(with event: NSEvent) {
            onKeyRelease(event)
        }

        override var acceptsFirstResponder: Bool {
            return true
        }
    }

    func makeNSView(context: Context) -> NSViewType {
        let view = NSViewType(onKeyPress: onKeyPress, onKeyRelease: onKeyRelease)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {}
}

#elseif os(iOS)
import UIKit

let upArrow = UIKeyCommand.inputUpArrow
let downArrow = UIKeyCommand.inputDownArrow
let leftArrow = UIKeyCommand.inputLeftArrow
let rightArrow = UIKeyCommand.inputRightArrow

struct KeyboardHandlingView: UIViewRepresentable {
    var onKeyPress: (UIKeyCommand) -> Void

    class UIViewType: UIView {
        var onKeyPress: (UIKeyCommand) -> Void

        init(onKeyPress: @escaping (UIKeyCommand) -> Void) {
            self.onKeyPress = onKeyPress
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var canBecomeFirstResponder: Bool {
            return true
        }

        override var keyCommands: [UIKeyCommand]? {
            return [
                UIKeyCommand(input: upArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
                UIKeyCommand(input: downArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
                UIKeyCommand(input: leftArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
                UIKeyCommand(input: rightArrow, modifierFlags: [], action: #selector(handleKeyCommand(_:))),
                UIKeyCommand(input: " ", modifierFlags: [], action: #selector(handleKeyCommand(_:))) // Space key to shoot
            ]
        }

        @objc func handleKeyCommand(_ command: UIKeyCommand) {
            onKeyPress(command)
        }
    }

    func makeUIView(context: Context) -> UIViewType {
        let view = UIViewType(onKeyPress: onKeyPress)
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {}
}
#endif

struct ContentView: View {
    struct Enemy {
        var position: CGSize
        var speed: CGFloat
    }
    
    struct PowerUp {
        var position: CGSize
        var isHoming: Bool
    }
    
    struct Bullet {
        var position: CGSize
        var isHoming: Bool
        
        func intersects(with enemy: Enemy) -> Bool {
            let bulletFrame = CGRect(x: position.width - 5, y: position.height - 5, width: 10, height: 10)
            let enemyFrame = CGRect(x: enemy.position.width, y: enemy.position.height, width: 50, height: 50)
            return bulletFrame.intersects(enemyFrame)
        }
    }

    struct EnemyChain {
        var enemies: [Enemy]
        var pattern: [CGSize]
        var currentStep: Int = 0
    }

    @State private var playerHealth: Int = 100
    @State private var bullets: [Bullet] = []
    @State private var enemyChains: [EnemyChain] = []
    @State private var powerUps: [PowerUp] = []
    @State private var hasPowerUp: Bool = false
    @State private var powerUpTimer: Timer? = nil
    @State private var planePosition: CGSize = .zero
    @State private var screenSize: CGSize = .zero
    @State private var isGameOver = false
    @State private var enemies: [Enemy] = []
    @State private var movementKeys = Set<String>()
    
    private let movementAmount: CGFloat = 6
    private let bulletSpeed: CGFloat = 10
    private let bulletOffset: CGFloat = 15
    private let enemySpeed: CGFloat = 2
    private let enemySpawnInterval: TimeInterval = 0.2

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.blue
                    .edgesIgnoringSafeArea(.all)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                if !isGameOver {
                    healthBar
                    
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .position(x: planePosition.width + 50, y: planePosition.height + 50)
                    
                    Image(systemName: "airplane")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(270))
                        .position(x: planePosition.width + 40, y: planePosition.height + 40)
                        .onAppear {
                            planePosition = CGSize(width: geometry.size.width / 2 - 50, height: geometry.size.height / 2 - 50)
                            screenSize = geometry.size
                            spawnEnemies(screenSize: geometry.size)
                            startEnemySpawning(screenSize: geometry.size)
                        }
                    
                    ForEach(bullets.indices, id: \.self) { index in
                        Circle()
                            .fill(bullets[index].isHoming ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                            .position(x: bullets[index].position.width, y: bullets[index].position.height)
                    }
                    
                    ForEach(enemies.indices, id: \.self) { index in
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 50, height: 50)
                            .position(x: enemies[index].position.width, y: enemies[index].position.height)
                    }
                    
                    ForEach(powerUps.indices, id: \.self) { index in
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 30, height: 30)
                            .position(x: powerUps[index].position.width, y: powerUps[index].position.height)
                    }
                    
                } else {
                    VStack {
                        Text("Game Over")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        
                        Button(action: {
                            restartGame(geometry: geometry)
                        }) {
                            Text("Restart")
                                .font(.title)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .background(KeyboardHandlingView { event in
#if os(macOS)
                handleKeyPressMac(event: event, screenSize: geometry.size)
#elseif os(iOS)
                handleKeyPressiOS(event: event, screenSize: geometry.size)
#endif
            } onKeyRelease: { event in
#if os(macOS)
                handleKeyReleaseMac(event: event)
#endif
            })
            .onReceive(Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()) { _ in
                updateBullets()
                updateEnemies()
                updatePowerUps()
                handleContinuousMovement(screenSize: geometry.size)
                checkCollisions()
            }
        }
    }
    
    var healthBar: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 20)
            
            Rectangle()
                .fill(Color.red)
                .frame(width: CGFloat(playerHealth) * 2, height: 20)
        }
        .cornerRadius(10)
        .padding()
    }
    
    func activatePowerUp() {
        hasPowerUp = true
        powerUpTimer?.invalidate()
        powerUpTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            hasPowerUp = false
        }
    }
    
    func handleKeyPressMac(event: NSEvent, screenSize: CGSize) {
        if let key = event.charactersIgnoringModifiers {
            if event.type == .keyDown {
                switch event.keyCode {
                case 126:
                    movementKeys.insert(upArrow)
                case 125:
                    movementKeys.insert(downArrow)
                case 123:
                    movementKeys.insert(leftArrow)
                case 124:
                    movementKeys.insert(rightArrow)
                case 49:
                    shootBullets()
                default:
                    break
                }
            }
        }
    }
    
    func handleKeyReleaseMac(event: NSEvent) {
        if let key = event.charactersIgnoringModifiers {
            switch event.keyCode {
            case 126:
                movementKeys.remove(upArrow)
            case 125:
                movementKeys.remove(downArrow)
            case 123:
                movementKeys.remove(leftArrow)
            case 124:
                movementKeys.remove(rightArrow)
            default:
                break
            }
        }
    }
    
#if os(iOS)
    func handleKeyPressiOS(event: UIKeyCommand, screenSize: CGSize) {
        if let key = event.input {
            if key == upArrow || key == downArrow || key == leftArrow || key == rightArrow {
                movementKeys.insert(key)
            }
            switch key {
            case upArrow:
                movePlane(by: CGSize(width: 0, height: -movementAmount), screenSize: screenSize)
            case downArrow:
                movePlane(by: CGSize(width: 0, height: movementAmount), screenSize: screenSize)
            case leftArrow:
                movePlane(by: CGSize(width: -movementAmount, height: 0), screenSize: screenSize)
            case rightArrow:
                movePlane(by: CGSize(width: movementAmount, height: 0), screenSize: screenSize)
            case " ":
                shootBullets()
            default:
                break
            }
        }
    }
#endif
    
    func movePlane(by offset: CGSize, screenSize: CGSize) {
        planePosition = CGSize(
            width: min(max(planePosition.width + offset.width, 0), screenSize.width - 100),
            height: min(max(planePosition.height + offset.height, 0), screenSize.height - 100)
        )
    }
    
    func handleContinuousMovement(screenSize: CGSize) {
        var moveOffset = CGSize.zero
        if movementKeys.contains(upArrow) {
            moveOffset.height -= movementAmount
        }
        if movementKeys.contains(downArrow) {
            moveOffset.height += movementAmount
        }
        if movementKeys.contains(leftArrow) {
            moveOffset.width -= movementAmount
        }
        if movementKeys.contains(rightArrow) {
            moveOffset.width += movementAmount
        }
        if moveOffset != .zero {
            movePlane(by: moveOffset, screenSize: screenSize)
        }
    }
    
    func shootBullets() {
        let leftBulletPosition = CGSize(width: planePosition.width + 35, height: planePosition.height)
        let rightBulletPosition = CGSize(width: planePosition.width + 65, height: planePosition.height)
        let isHoming = hasPowerUp
        bullets.append(Bullet(position: leftBulletPosition, isHoming: isHoming))
        bullets.append(Bullet(position: rightBulletPosition, isHoming: isHoming))
    }
    
    func updateBullets() {
        for i in bullets.indices.reversed() {
            if bullets[i].isHoming {
                if let nearestEnemy = findNearestEnemy(to: bullets[i].position) {
                    let direction = calculateDirection(from: bullets[i].position, to: nearestEnemy.position)
                    bullets[i].position.width += direction.width * bulletSpeed
                    bullets[i].position.height += direction.height * bulletSpeed
                }
            } else {
                bullets[i].position.height -= bulletSpeed
            }
            
            if bullets[i].position.height < 0 {
                bullets.remove(at: i)
            }
        }
    }
    
    func findNearestEnemy(to bulletPosition: CGSize) -> Enemy? {
        return enemies.min(by: {
            distance(from: bulletPosition, to: $0.position) < distance(from: bulletPosition, to: $1.position)
        })
    }
    
    func calculateDirection(from start: CGSize, to end: CGSize) -> CGSize {
        let dx = end.width - start.width
        let dy = end.height - start.height
        let length = sqrt(dx * dx + dy * dy)
        return CGSize(width: dx / length, height: dy / length)
    }
    
    func distance(from start: CGSize, to end: CGSize) -> CGFloat {
        return sqrt(pow(end.width - start.width, 2) + pow(end.height - start.height, 2))
    }
    
    func updatePowerUps() {
        for i in powerUps.indices.reversed() {
            powerUps[i].position.height += 2
            
            if planeIntersects(with: powerUps[i].position) {
                powerUps.remove(at: i)
                activatePowerUp()
            }
        }
    }
    
    func spawnPowerUp(at position: CGSize) {
        let newPowerUp = PowerUp(position: position, isHoming: true)
        powerUps.append(newPowerUp)
    }
    
    func spawnEnemies(screenSize: CGSize) {
        let spawnEdge = Int.random(in: 0...2)
        var position: CGSize
        
        switch spawnEdge {
        case 0:
            position = CGSize(width: 0, height: CGFloat.random(in: 0...screenSize.height))
        case 1:
            position = CGSize(width: screenSize.width, height: CGFloat.random(in: 0...screenSize.height))
        default:
            position = CGSize(width: CGFloat.random(in: 0...screenSize.width), height: 0)
        }
        
        let speed = CGFloat.random(in: 2...6)
        let newEnemy = Enemy(position: position, speed: speed)
        enemies.append(newEnemy)
    }
    
    func startEnemySpawning(screenSize: CGSize) {
        Timer.scheduledTimer(withTimeInterval: enemySpawnInterval, repeats: true) { _ in
            spawnEnemies(screenSize: screenSize)
        }
    }
    
    func spawnEnemyChain(screenSize: CGSize, pattern: [CGSize], numberOfEnemies: Int, spacing: CGFloat) {
        var chain = EnemyChain(enemies: [], pattern: pattern)
        
        for i in 0..<numberOfEnemies {
            let position = pattern.first ?? CGSize(width: screenSize.width / 2, height: 0)
            let enemy = Enemy(position: position, speed: enemySpeed)
            chain.enemies.append(enemy)
        }
        
        for i in 1..<chain.enemies.count {
            chain.enemies[i].position.height = chain.enemies[i - 1].position.height - spacing
        }
        
        enemyChains.append(chain)
    }
    
    func updateEnemies() {
        for i in enemies.indices.reversed() {
            let dx = planePosition.width - enemies[i].position.width
            let dy = planePosition.height - enemies[i].position.height
            
            let randomOffsetX = CGFloat.random(in: -0.5...0.5)
            let randomOffsetY = CGFloat.random(in: -0.5...0.5)
            
            let directionX = dx + randomOffsetX
            let directionY = dy + randomOffsetY
            
            let length = sqrt(directionX * directionX + directionY * directionY)
            let normalizedX = directionX / length
            let normalizedY = directionY / length
            
            enemies[i].position.width += normalizedX * enemies[i].speed
            enemies[i].position.height += normalizedY * enemies[i].speed
            
            if planeIntersects(with: enemies[i].position) {
                enemies.remove(at: i)
            }
        }
    }
    
    func planeIntersects(with enemyPosition: CGSize) -> Bool {
        let planeRect = CGRect(x: planePosition.width, y: planePosition.height, width: 100, height: 100)
        let enemyRect = CGRect(x: enemyPosition.width, y: enemyPosition.height, width: 50, height: 50)
        return planeRect.intersects(enemyRect)
    }
    
    func checkCollisions() {
        for bulletIndex in bullets.indices.reversed() {
            for enemyIndex in enemies.indices.reversed() {
                if bullets[bulletIndex].intersects(with: enemies[enemyIndex]) {
                    let enemyPosition = enemies[enemyIndex].position
                    bullets.remove(at: bulletIndex)
                    enemies.remove(at: enemyIndex)
                    
                    if Double.random(in: 0...1) < 0.05 {
                        spawnPowerUp(at: enemyPosition)
                    }
                    break
                }
            }
        }

        for enemyIndex in enemies.indices.reversed() {
            if planeIntersects(with: enemies[enemyIndex].position) {
                enemies.remove(at: enemyIndex)
                playerHealth -= 10

                if playerHealth <= 0 {
                    isGameOver = true
                }
            }
        }
    }

    func restartGame(geometry: GeometryProxy) {
        isGameOver = false
        playerHealth = 100
        planePosition = CGSize(width: geometry.size.width / 2 - 50, height: geometry.size.height / 2 - 50)
        bullets.removeAll()
        enemies.removeAll()
        powerUps.removeAll()
        startEnemySpawning(screenSize: geometry.size)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
