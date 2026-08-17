import SwiftUI

private let bgColor = Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x24 / 255)
private let offColor = Color(red: 60 / 255, green: 60 / 255, blue: 63 / 255)
private let onColor = Color(red: 255 / 255, green: 200 / 255, blue: 87 / 255)

struct PowerCircleButton: View {
    let isOn: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var pop: CGFloat = 1.0

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                pop = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                    pop = 1.0
                }
            }
            action()
        }) {
            ZStack {
                if isOn {
                    Circle()
                        .fill(onColor.opacity(0.18))
                        .frame(width: size * 1.35, height: size * 1.35)
                        .blur(radius: 12)
                    Circle()
                        .fill(onColor.opacity(0.28))
                        .frame(width: size * 1.15, height: size * 1.15)
                        .blur(radius: 6)
                }
                Circle()
                    .fill(isOn ? onColor : offColor)
                    .frame(width: size, height: size)
            }
            .scaleEffect(pop)
            .animation(.easeInOut(duration: 0.3), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

struct DeviceRowView: View {
    @ObservedObject var manager: BluetoothManager
    let device: GoveeDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(device.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(device.status)
                    .font(.system(size: 11))
                    .foregroundColor(device.isConnected ? Color(red: 0.2, green: 0.78, blue: 0.35) : .orange)
            }

            HStack(spacing: 15) {
                PowerCircleButton(isOn: device.isOn, size: 46) {
                    manager.setPower(name: device.id, on: !device.isOn)
                }

                Slider(
                    value: Binding(
                        get: { device.brightness },
                        set: { manager.setBrightness(name: device.id, percent: $0) }
                    ),
                    in: 0...100
                )
                .tint(onColor)
            }
        }
        .padding(15)
        .background(Color(red: 0x2f / 255, green: 0x2f / 255, blue: 0x31 / 255))
        .cornerRadius(16)
    }
}

struct ContentView: View {
    @StateObject private var manager = BluetoothManager()
    @State private var allOn = true

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("LED")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 30)

                VStack(spacing: 8) {
                    PowerCircleButton(isOn: allOn, size: 110) {
                        allOn.toggle()
                        manager.setAllPower(on: allOn)
                    }
                    Text("ALLE")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 10)

                VStack(spacing: 12) {
                    ForEach(manager.devices) { device in
                        DeviceRowView(manager: manager, device: device)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }
}
