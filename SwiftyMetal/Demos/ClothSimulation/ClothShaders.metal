#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Types

struct ClothUniforms {
    float2 gridSize;       // (cols, rows)
    float restLength;      // structural rest length
    float damping;         // velocity damping factor
    float dt;              // time step
    float vertexForce;     // external force multiplier
    float simSpeed;        // simulation speed multiplier
    int enableSim;         // 0 = paused, 1 = running
    int enableVertexShader;// 0 = flat, 1 = displaced
    float time;            // elapsed time for wind
    float4x4 mvpMatrix;
    float4x4 modelMatrix;
    float3 lightPosition;
    float3 cameraPosition;
};

struct ClothNode {
    float3 position;
    float3 oldPosition;
    float3 restPosition;   // target rest shape to spring back to
    float mass;
    int pinned;            // 1 = pinned (immovable)
    float2 uv;
};

// MARK: - Vertex / Fragment types

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
};

// MARK: - Helpers

static float3 computeTriNormal(float3 a, float3 b, float3 c) {
    return normalize(cross(b - a, c - a));
}

// MARK: - Compute Kernel: Verlet Integration + Constraints

kernel void clothSimulation(
    device ClothNode *nodes [[buffer(0)]],
    constant ClothUniforms &u [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    int cols = int(u.gridSize.x);
    int rows = int(u.gridSize.y);
    int total = cols * rows;
    if (int(gid) >= total) return;
    if (u.enableSim == 0) return;

    device ClothNode &node = nodes[gid];
    if (node.pinned == 1) return;

    float dt = u.dt * u.simSpeed;

    // Spring back to rest position (defines the hanging shape)
    float3 toRest = node.restPosition - node.position;
    float3 springForce = toRest * 25.0; // very stiff paper - snaps back quickly

    // Wind (only active when vertexForce > 0)
    float3 wind = float3(0.0);
    if (u.vertexForce > 0.01) {
        float windPhase = u.time * 1.5 + node.position.x * 0.3 + node.position.y * 0.2;
        wind = float3(
            sin(windPhase) * 0.15,
            cos(windPhase * 0.5) * 0.05,
            sin(windPhase * 0.8) * 0.1
        ) * u.vertexForce;
    }

    float3 totalForce = wind + springForce;

    // Verlet integration
    float3 vel = (node.position - node.oldPosition) * u.damping;

    // Deadzone: if very close to rest and barely moving, snap to rest
    float distToRest = length(toRest);
    float speed = length(vel);
    if (distToRest < 0.0005 && speed < 0.0005) {
        node.oldPosition = node.restPosition;
        node.position = node.restPosition;
        return;
    }

    float3 newPos = node.position + vel + totalForce * dt * dt;
    node.oldPosition = node.position;
    node.position = newPos;
}

// MARK: - Compute Kernel: Constraint Satisfaction

kernel void clothConstraints(
    device ClothNode *nodes [[buffer(0)]],
    constant ClothUniforms &u [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    int cols = int(u.gridSize.x);
    int rows = int(u.gridSize.y);
    int total = cols * rows;
    if (int(gid) >= total) return;
    if (u.enableSim == 0) return;

    int x = int(gid) % cols;
    int y = int(gid) / cols;

    device ClothNode &node = nodes[gid];
    if (node.pinned == 1) return;

    float structural = u.restLength;
    float diagonal = structural * 1.41421356;
    float bending = structural * 2.0;

    // Helper lambda-like inline constraint solve
    #define SOLVE_CONSTRAINT(otherIdx, restDist) { \
        device ClothNode &other = nodes[otherIdx]; \
        float3 delta = node.position - other.position; \
        float dist = length(delta); \
        if (dist > 0.0001) { \
            float diff = (dist - restDist) / dist; \
            if (other.pinned == 1) { \
                node.position -= delta * diff; \
            } else { \
                node.position -= delta * 0.5 * diff; \
            } \
        } \
    }

    // Structural constraints (horizontal + vertical neighbors)
    if (x > 0)        SOLVE_CONSTRAINT(y * cols + (x - 1), structural)
    if (x < cols - 1) SOLVE_CONSTRAINT(y * cols + (x + 1), structural)
    if (y > 0)        SOLVE_CONSTRAINT((y - 1) * cols + x, structural)
    if (y < rows - 1) SOLVE_CONSTRAINT((y + 1) * cols + x, structural)

    // Shear constraints (diagonal neighbors)
    if (x > 0 && y > 0)               SOLVE_CONSTRAINT((y - 1) * cols + (x - 1), diagonal)
    if (x < cols - 1 && y > 0)        SOLVE_CONSTRAINT((y - 1) * cols + (x + 1), diagonal)
    if (x > 0 && y < rows - 1)        SOLVE_CONSTRAINT((y + 1) * cols + (x - 1), diagonal)
    if (x < cols - 1 && y < rows - 1) SOLVE_CONSTRAINT((y + 1) * cols + (x + 1), diagonal)

    // Bending constraints (skip-one neighbors)
    if (x > 1)        SOLVE_CONSTRAINT(y * cols + (x - 2), bending)
    if (x < cols - 2) SOLVE_CONSTRAINT(y * cols + (x + 2), bending)
    if (y > 1)        SOLVE_CONSTRAINT((y - 2) * cols + x, bending)
    if (y < rows - 2) SOLVE_CONSTRAINT((y + 2) * cols + x, bending)

    #undef SOLVE_CONSTRAINT
}

// MARK: - Vertex Shader

vertex VertexOut clothVertex(
    device ClothNode *nodes [[buffer(0)]],
    constant ClothUniforms &u [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    // vid is already the node index (remapped by drawIndexedPrimitives)
    int cols = int(u.gridSize.x);
    int rows = int(u.gridSize.y);
    int x = int(vid) % cols;
    int y = int(vid) / cols;

    float3 pos = nodes[vid].position;

    // Compute normal from neighboring vertices
    float3 normal = float3(0, 0, 1);
    int count = 0;

    if (x > 0 && y > 0) {
        float3 left = nodes[y * cols + (x - 1)].position;
        float3 up = nodes[(y - 1) * cols + x].position;
        normal += computeTriNormal(pos, left, up);
        count++;
    }
    if (x < cols - 1 && y > 0) {
        float3 right = nodes[y * cols + (x + 1)].position;
        float3 up = nodes[(y - 1) * cols + x].position;
        normal += computeTriNormal(pos, up, right);
        count++;
    }
    if (x > 0 && y < rows - 1) {
        float3 left = nodes[y * cols + (x - 1)].position;
        float3 down = nodes[(y + 1) * cols + x].position;
        normal += computeTriNormal(pos, down, left);
        count++;
    }
    if (x < cols - 1 && y < rows - 1) {
        float3 right = nodes[y * cols + (x + 1)].position;
        float3 down = nodes[(y + 1) * cols + x].position;
        normal += computeTriNormal(pos, right, down);
        count++;
    }
    if (count > 0) normal = normalize(normal);

    float3 worldPos = (u.modelMatrix * float4(pos, 1.0)).xyz;

    VertexOut out;
    out.position = u.enableVertexShader == 1 ? u.mvpMatrix * float4(pos, 1.0) : u.mvpMatrix * float4(pos, 1.0);
    out.worldPosition = worldPos;
    out.normal = normalize((u.modelMatrix * float4(normal, 0.0)).xyz);
    out.uv = nodes[vid].uv;
    return out;
}

// MARK: - Fragment Shader (Phong Lighting)

fragment float4 clothFragment(
    VertexOut in [[stage_in]],
    texture2d<float> receiptTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float4 texColor = receiptTexture.sample(texSampler, in.uv);
    // Ensure alpha is never 0 (fallback to opaque white if texture missing)
    if (texColor.a < 0.01) {
        texColor = float4(1.0, 1.0, 1.0, 1.0);
    }

    float3 N = normalize(in.normal);
    float3 L = normalize(float3(2.0, 2.0, 6.0) - in.worldPosition);
    float3 V = normalize(float3(0.0, -0.5, 6.0) - in.worldPosition);
    float3 H = normalize(L + V);

    // Ambient
    float3 ambient = 0.4 * texColor.rgb;

    // Diffuse
    float diff = max(dot(N, L), 0.0);
    // Also light from behind for double-sided
    float diffBack = max(dot(-N, L), 0.0) * 0.5;
    float3 diffuse = (diff + diffBack) * texColor.rgb;

    // Specular
    float spec = pow(max(dot(N, H), 0.0), 32.0);
    float3 specular = spec * float3(0.3);

    // Paper-like subsurface scattering approximation
    float sss = max(dot(-N, L), 0.0) * 0.15;
    float3 subsurface = sss * texColor.rgb;

    float3 color = ambient + diffuse + specular + subsurface;
    return float4(color, 1.0);
}
