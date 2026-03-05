//
//  BodyMapSceneKitView.swift
//  Muscu
//
//  Rôle : Vue 3D du corps (SceneKit) pour sélectionner les zones sensibles/blessées par tap.
//  Utilisé par : OnboardingStep4View.
//

import SwiftUI
import SceneKit

// MARK: - Zones tappables (noms des nœuds)

enum BodyZoneId: String, CaseIterable {
    case head
    case neck
    case shoulder_left
    case shoulder_right
    case elbow_left
    case elbow_right
    case wrist_left
    case wrist_right
    case back_upper
    case back_lower
    case hip_left
    case hip_right
    case knee_left
    case knee_right
    case ankle_left
    case ankle_right
}

// MARK: - Représentable UIKit (SCNView)

struct BodyMapSceneKitView: UIViewRepresentable {
    var selectedZoneIds: Set<String>
    var onZoneTapped: ((String) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = buildBodyScene(selectedZoneIds: selectedZoneIds)
        sceneView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tap)
        context.coordinator.sceneView = sceneView
        context.coordinator.onZoneTapped = onZoneTapped
        context.coordinator.selectedZoneIds = selectedZoneIds

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.selectedZoneIds = selectedZoneIds
        guard let scene = sceneView.scene else { return }
        updateMaterials(in: scene.rootNode, selected: selectedZoneIds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func buildBodyScene(selectedZoneIds: Set<String>) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.6, 2.2)
        cameraNode.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 600
        directional.position = SCNVector3(1, 2, 2)
        directional.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(directional)

        let body = buildHumanoidBody(selected: selectedZoneIds)
        scene.rootNode.addChildNode(body)

        return scene
    }

    private func buildHumanoidBody(selected: Set<String>) -> SCNNode {
        let root = SCNNode()
        root.name = "bodyRoot"

        let capsule = { (name: String, height: CGFloat, radius: CGFloat, y: Float) -> SCNNode in
            let geo = SCNCapsule(capRadius: radius, height: height)
            let node = SCNNode(geometry: geo)
            node.name = name
            node.position = SCNVector3(0, y, 0)
            node.geometry?.firstMaterial?.diffuse.contents = selected.contains(name) ? UIColor.systemRed : UIColor.systemTeal.withAlphaComponent(0.85)
            node.geometry?.firstMaterial?.specular.contents = UIColor.white
            node.geometry?.firstMaterial?.shininess = 0.3
            return node
        }

        func makeSphere(name: String, radius: CGFloat, y: Float, x: Float = 0) -> SCNNode {
            let geo = SCNSphere(radius: radius)
            let node = SCNNode(geometry: geo)
            node.name = name
            node.position = SCNVector3(x, y, 0)
            node.geometry?.firstMaterial?.diffuse.contents = selected.contains(name) ? UIColor.systemRed : UIColor.systemTeal.withAlphaComponent(0.85)
            node.geometry?.firstMaterial?.specular.contents = UIColor.white
            return node
        }

        // Tête, cou
        root.addChildNode(makeSphere(name: "head", radius: 0.12, y: 1.42))
        root.addChildNode(capsule("neck", 0.12, 0.04, 1.28))

        // Tronc
        root.addChildNode(capsule("back_upper", 0.35, 0.14, 1.0))
        root.addChildNode(capsule("back_lower", 0.28, 0.12, 0.62))

        // Épaules
        root.addChildNode(makeSphere(name: "shoulder_left", radius: 0.06, y: 1.18, x: -0.18))
        root.addChildNode(makeSphere(name: "shoulder_right", radius: 0.06, y: 1.18, x: 0.18))

        // Bras (coude, poignet)
        let armY: Float = 0.95
        root.addChildNode(makeSphere(name: "elbow_left", radius: 0.045, y: armY, x: -0.32))
        root.addChildNode(makeSphere(name: "elbow_right", radius: 0.045, y: armY, x: 0.32))
        root.addChildNode(makeSphere(name: "wrist_left", radius: 0.035, y: 0.72, x: -0.42))
        root.addChildNode(makeSphere(name: "wrist_right", radius: 0.035, y: 0.72, x: 0.42))

        // Hanches
        root.addChildNode(makeSphere(name: "hip_left", radius: 0.055, y: 0.42, x: -0.12))
        root.addChildNode(makeSphere(name: "hip_right", radius: 0.055, y: 0.42, x: 0.12))

        // Genoux, chevilles
        root.addChildNode(makeSphere(name: "knee_left", radius: 0.05, y: 0.18, x: -0.1))
        root.addChildNode(makeSphere(name: "knee_right", radius: 0.05, y: 0.18, x: 0.1))
        root.addChildNode(makeSphere(name: "ankle_left", radius: 0.04, y: -0.08, x: -0.1))
        root.addChildNode(makeSphere(name: "ankle_right", radius: 0.04, y: -0.08, x: 0.1))

        return root
    }

    private func updateMaterials(in node: SCNNode, selected: Set<String>) {
        if let name = node.name, BodyZoneId(rawValue: name) != nil {
            node.geometry?.firstMaterial?.diffuse.contents = selected.contains(name) ? UIColor.systemRed : UIColor.systemTeal.withAlphaComponent(0.85)
        }
        for child in node.childNodes {
            updateMaterials(in: child, selected: selected)
        }
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        var sceneView: SCNView?
        var onZoneTapped: ((String) -> Void)?
        var selectedZoneIds: Set<String> = []

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = sceneView else { return }
            let location = gesture.location(in: view)
            let results = view.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = results.first, let nodeName = hit.node.name else { return }
            if BodyZoneId(rawValue: nodeName) != nil {
                onZoneTapped?(nodeName)
            }
        }
    }
}
