import SwiftData
import SwiftUI
import PhotosUI

struct RootView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var phone = IPhoneCameraSource()
  @StateObject private var glasses = MetaGlassesSource()
  @StateObject private var controller = ScanController()
  @State private var showHistory = false
  @State private var showGlasses = false
  @State private var selectedPhoto: PhotosPickerItem?

  var body: some View {
    ZStack {
      FVColor.ink.ignoresSafeArea()
      if controller.selectedSource == .metaGlasses, let image = glasses.previewImage {
        Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
      } else {
        CameraPreview(session: phone.session).ignoresSafeArea()
      }
      CameraChrome(
        controller: controller,
        capture: { Task { await controller.scan(using: phone, glasses: glasses) } },
        history: { showHistory = true }, glasses: { showGlasses = true }, selectedPhoto: $selectedPhoto)
      if (phone.permissionDenied || phone.cameraUnavailable) && controller.selectedSource == .iPhone {
        CameraPermissionOverlay(selectedPhoto: $selectedPhoto, unavailable: phone.cameraUnavailable,
                                history: { showHistory = true })
      }
      if controller.phase == .capturing || controller.phase == .analyzing {
        WorkingOverlay(phase: controller.phase)
      }
      if controller.phase == .result, let scan = controller.activeScan {
        ResultView(scan: scan, controller: controller).zIndex(5)
      }
    }
    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: controller.phase)
    .task {
      controller.attach(context)
      await phone.start()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task {
          await controller.syncPending()
          if controller.phase == .camera {
            if controller.selectedSource == .iPhone { await phone.start() }
            else { _ = await glasses.connectAndPreview() }
          }
        }
      } else {
        controller.speaker.stop()
        phone.stop()
        glasses.stop()
      }
    }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task {
        defer { selectedPhoto = nil }
        do {
          guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CaptureError.noImageData
          }
          await controller.importPhoto(data)
        } catch { controller.shopperMessage = "That photo could not be opened. Choose another photo." }
      }
    }
    .onChange(of: controller.selectedSource) { _, source in
      Task {
        if source == .iPhone {
          glasses.stop()
          await phone.start()
        } else {
          phone.stop()
        }
      }
    }
    .onChange(of: controller.phase) { _, phase in
      if phase == .result {
        phone.stop()
        glasses.stop()
      } else if phase == .camera && scenePhase == .active {
        Task {
          if controller.selectedSource == .iPhone { await phone.start() }
          else { _ = await glasses.connectAndPreview() }
        }
      }
    }
    .onChange(of: glasses.captureButtonRequest) { _, _ in
      guard controller.selectedSource == .metaGlasses, controller.phase == .camera else { return }
      Task { await controller.scan(using: phone, glasses: glasses) }
    }
    .onOpenURL { url in Task { await glasses.handle(url: url) } }
    .sheet(isPresented: $showHistory) { HistoryView(controller: controller) }
    .sheet(isPresented: $showGlasses) {
      GlassesSheet(glasses: glasses, controller: controller).presentationDetents([.medium, .large])
    }
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(20))
        if !Task.isCancelled { await controller.syncPending() }
      }
    }
    .alert(
      "FreshVision",
      isPresented: Binding(
        get: { controller.shopperMessage != nil && controller.phase == .camera },
        set: { if !$0 { controller.shopperMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(controller.shopperMessage ?? "")
    }
  }
}

private struct CameraChrome: View {
  @ObservedObject var controller: ScanController
  let capture, history, glasses: () -> Void
  @Binding var selectedPhoto: PhotosPickerItem?
  var body: some View {
    VStack {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("FRESHVISION").font(.system(size: 13, weight: .black, design: .rounded)).tracking(
            2.1)
          Text(
            controller.selectedSource == .metaGlasses
              ? "Seeing through your glasses" : "Is it worth buying?"
          ).font(.system(size: 17, weight: .semibold, design: .rounded))
        }.foregroundStyle(FVColor.cream)
        Spacer()
        Button(action: glasses) {
          Image(systemName: "eyeglasses").font(.system(size: 19, weight: .bold)).frame(
            width: 46, height: 46
          ).background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Meta glasses")
        .accessibilityHint("Connect glasses or choose the glasses camera")
      }.padding(.horizontal, 22).padding(.top, 12)
      Spacer()
      RoundedRectangle(cornerRadius: 40).stroke(FVColor.cream.opacity(0.86), lineWidth: 3).frame(
        width: 292, height: 360
      )
      .overlay(alignment: .top) {
        Text("ONE FRUIT").font(.system(size: 12, weight: .black, design: .rounded)).tracking(1.8)
          .foregroundStyle(FVColor.ink).padding(.horizontal, 14).padding(.vertical, 8).background(
            FVColor.cream, in: Capsule()
          ).offset(y: -17)
      }
      Spacer()
      HStack {
        Button(action: history) {
          Label("History", systemImage: "clock.arrow.circlepath").labelStyle(.iconOnly).font(
            .title2
          ).frame(width: 70, height: 48)
        }
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 44, height: 48)
        }.accessibilityLabel("Choose a fruit photo")
        Spacer()
        Button(action: capture) {
          ZStack {
            Circle().fill(FVColor.cream).frame(width: 88, height: 88)
            Circle().stroke(FVColor.ink, lineWidth: 4).frame(width: 72, height: 72)
            Circle().fill(FVColor.tomato).frame(width: 56, height: 56)
          }
        }.accessibilityLabel("Scan fruit")
        Spacer()
        VStack(spacing: 4) {
          Image(systemName: controller.selectedSource == .metaGlasses ? "eyeglasses" : "iphone")
          Text(controller.selectedSource == .metaGlasses ? "Glasses" : "iPhone").font(
            .caption2.bold())
        }.frame(width: 70, height: 48)
      }.foregroundStyle(FVColor.cream).padding(.horizontal, 24).padding(.bottom, 24)
      Text("Photos are saved privately and sent for AI analysis. Delete them from History.")
        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(FVColor.cream.opacity(0.72))
        .padding(.horizontal, 28).padding(.bottom, 8)
    }.background(
      LinearGradient(
        colors: [.black.opacity(0.72), .clear, .clear, .black.opacity(0.78)], startPoint: .top,
        endPoint: .bottom
      ).ignoresSafeArea())
  }
}

private struct WorkingOverlay: View {
  let phase: ScanController.Phase
  var body: some View {
    ZStack {
      Color.black.opacity(0.58).ignoresSafeArea()
      VStack(spacing: 20) {
        ProgressView().tint(FVColor.lime).scaleEffect(1.6)
        Text(phase == .capturing ? "Taking a closer look" : "Checking color, skin and shape").font(
          .title3.bold()
        ).foregroundStyle(FVColor.cream)
      }
    }.accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
  }
}

private struct CameraPermissionOverlay: View {
  @Binding var selectedPhoto: PhotosPickerItem?
  let unavailable: Bool
  let history: () -> Void
  var body: some View {
    ZStack {
      FVColor.ink.opacity(0.96).ignoresSafeArea()
      VStack(spacing: 18) {
        Image(systemName: "camera.fill").font(.system(size: 42, weight: .bold)).foregroundStyle(
          FVColor.lime)
        Text(unavailable ? "Choose a fruit photo" : "Turn on camera access").font(.system(size: 32, weight: .black, design: .rounded))
          .foregroundStyle(FVColor.cream)
        Text(
          unavailable ? "The camera is unavailable on this device. You can check a fruit photo from your library."
            : "Allow Camera in Settings, or choose a fruit photo from your library."
        ).font(.title3).multilineTextAlignment(.center).foregroundStyle(FVColor.cream.opacity(0.82))
        if !unavailable { Button("Open Settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }.buttonStyle(FVPrimaryButtonStyle(color: FVColor.lime)) }
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          Label("Choose a fruit photo", systemImage: "photo.on.rectangle")
        }.buttonStyle(FVPrimaryButtonStyle(color: FVColor.cream))
        Button("View history", action: history).foregroundStyle(FVColor.cream).font(.headline)
      }.padding(28)
    }
  }
}
