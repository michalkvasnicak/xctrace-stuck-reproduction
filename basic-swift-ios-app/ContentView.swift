import SwiftUI

struct ContentView: View {
    @State private var count = 0
    @State private var isRunningWorkload = false
    @State private var workloadResult = "Not run yet"

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 1.0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Basic Swift iPhone App")
                    .font(.title.bold())

                Text("Count: \(count)")
                    .font(.headline)

                Button("Increment") {
                    count += 1
                }
                .buttonStyle(.borderedProminent)

                Button(isRunningWorkload ? "Running CPU workload..." : "Run CPU Workload") {
                    Task {
                        await runCPUWorkload()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRunningWorkload)

                Text(workloadResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 12, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runCPUWorkload() async {
        isRunningWorkload = true
        defer { isRunningWorkload = false }

        let start = Date()
        let digest = await ProfilerWorkload.run()
        let elapsed = Date().timeIntervalSince(start)
        workloadResult = String(format: "Digest: %@ in %.2fs", digest, elapsed)
    }
}

#Preview {
    ContentView()
}
