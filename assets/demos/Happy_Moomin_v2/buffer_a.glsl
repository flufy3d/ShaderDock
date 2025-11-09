// MIT License

// Buffer A - Model and navigation
// Inputs: Buffer A, Keyboard

#define keyboardTexture(coord) texture(iChannel1, (coord) / vec2(256.0, 3.0))

// steps view values
int marchSteps = 0;
int marchTransparentSteps = 0;
int marchReflectionSteps = 0;
int marchShadowSteps = 0;

// Consts
const mat2 rotation_0 = mat2(1.0, 0.0, 0.0, 1.0);
const mat2 rotation_1 = mat2(0.9998476, 0.0174524, -0.0174524, 0.9998476);
const mat2 rotation_7_5 = mat2(0.9914448, 0.1305261, -0.1305261, 0.9914448);
const mat2 rotation_10 = mat2(0.9848077, 0.1736481, -0.1736481, 0.9848077);
const mat2 rotation_15 = mat2(0.9659258, 0.258819, -0.258819, 0.9659258);
const mat2 rotation_20 = mat2(0.9396926, 0.342020, -0.342020, 0.9396926);
const mat2 rotation_25 = mat2(0.9063077, 0.422618, -0.422618, 0.9063077);
const mat2 rotation_30 = mat2(0.8660254, 0.5, -0.5, 0.8660254);
const mat2 rotation_45 = mat2(0.7071067, 0.7071067, -0.7071067, 0.7071067);
const mat2 rotation_60 = mat2(0.5, 0.8660254, -0.8660254, 0.5);
const mat2 rotation_90 = mat2(0.0, 1.0, -1.0, 0.0);
const mat2 rotation_120 = mat2(-0.5, 0.8660254, -0.8660254, -0.5);
const mat2 rotation_145 = mat2(-0.8191520, 0.5735764, -0.5735764, -0.8191520);
const mat2 rotation_180 = mat2(-1.0, 0.0, 0.0, -1.0);

const mat2 rotation_n1 = mat2(0.9998476, -0.0174524, 0.0174524, 0.9998476);
const mat2 rotation_n7_5 = mat2(0.9914448, -0.1305261, 0.1305261, 0.9914448);
const mat2 rotation_n10 = mat2(0.9848077, -0.1736481, 0.1736481, 0.9848077);
const mat2 rotation_n15 = mat2(0.9659258, -0.258819, 0.258819, 0.9659258);
const mat2 rotation_n20 = mat2(0.9396926, -0.342020, 0.342020, 0.9396926);
const mat2 rotation_n25 = mat2(0.9063077, -0.422618, 0.422618, 0.9063077);
const mat2 rotation_n30 = mat2(0.8660254, -0.5, 0.5, 0.8660254);
const mat2 rotation_n36 = mat2(0.8090169, -0.5877852, 0.5877852, 0.8090169);
const mat2 rotation_n45 = mat2(0.7071067, -0.7071067, 0.7071067, 0.7071067);
const mat2 rotation_n60 = mat2(0.5, -0.8660254, 0.8660254, 0.5);
const mat2 rotation_n90 = mat2(0.0, -1.0, 1.0, 0.0);
const mat2 rotation_n120 = mat2(-0.5, -0.8660254, 0.8660254, -0.5);
const mat2 rotation_n145 = mat2(-0.8191520, -0.5735764, 0.5735764, -0.8191520);
const mat2 rotation_n180 = mat2(-1.0, -0.0, 0.0, -1.0);


// -- Moomin --

// - Keyframe contains animatable rotation angles (vec3), that could be mixed with
// other keyframes values
// - Pose contains quaternion rotation values (vec4) that are calculated based on
// the applied keyframe (using setPose)

struct HeadPose
{
    vec4 rotation;
    vec2 eyesDirection;
    vec4 earsRotation;
    float eyesOpen;
    float eyelidsOffset;
    float eyebrowsHeight;
    float cheeksHeight;
    float cheeksBlush;
    float mouthHeight;
    float mouthOpen;
};

struct ArmPose
{
    vec4 shoulderRotation;
    vec4 armRotation;
    vec4 elbowRotation;
    vec4 wristRotation;
    float fingersSpread;
    float fingersFold;
};

struct LegPose
{
    vec4 baseRotation;
    vec4 rotation;
    vec4 kneeRotation;
    vec4 footRotation;
    float toesAngle;
};

struct TailPose
{
    vec4 baseRotation;
    vec4 rotation;
    float curve;
};

struct Pose
{
    vec3 offset;
    vec4 rotation;
    vec4 bodyCurve;
    HeadPose head;
    ArmPose rightArm;
    ArmPose leftArm;
    LegPose rightLeg;
    LegPose leftLeg;
    TailPose tail;
} pose;

// Keyframe

struct HeadKeyframe
{
    vec3 rotation;
    vec2 eyesDirection;
    vec3 earsRotation;
    float eyesOpen;
    float eyelidsOffset;
    float eyebrowsHeight;
    float cheeksHeight;
    float cheeksBlush;
    float mouthHeight;
    float mouthOpen;
};

struct ArmKeyframe
{
    vec3 shoulderRotation;
    vec3 armRotation;
    vec3 elbowRotation;
    vec3 wristRotation;
    float fingersSpread;
    float fingersFold;
};

struct LegKeyframe
{
    vec3 baseRotation;
    vec3 rotation;
    vec3 kneeRotation;
    vec3 footRotation;
    float toesAngle;
};

struct TailKeyframe
{
    vec3 baseRotation;
    vec3 rotation;
    float curve;
};

struct Keyframe
{
    vec3 offset;
    vec3 rotation;
    vec3 bodyCurve;
    HeadKeyframe head;
    ArmKeyframe rightArm;
    ArmKeyframe leftArm;
    LegKeyframe rightLeg;
    LegKeyframe leftLeg;
    TailKeyframe tail;
};

Keyframe emptyKeyframe = Keyframe(
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), // body
    HeadKeyframe(vec3(0.0, 0.0, 0.0), vec2(0.0, 0.0), vec3(0.0), 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), // head
    ArmKeyframe(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 0.0, 0.0), // right arm
    ArmKeyframe(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 0.0, 0.0), // left arm
    LegKeyframe(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 0.0), // right leg
    LegKeyframe(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 0.0), // left leg
    TailKeyframe(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), 0.5)); // tail

Keyframe happyKeyframe = Keyframe(
    vec3(0.0, 0.7, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.225, -0.3, 0.0), // body
    HeadKeyframe(vec3(-0.125, 0.325, -0.075), vec2(0.0, 0.0), vec3(0.0), 0.0, -0.8, 0.1, 1.0, 0.0, 0.0, 0.0), // head
    ArmKeyframe(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.1, 0.4), vec3(0.0, 0.1, 0.0), vec3(0.0, 0.1, -0.3), 0.0, -0.1), // right arm
    ArmKeyframe(vec3(0.0, 0.0, -0.2), vec3(0.0, -0.4, 0.3), vec3(0.0, 0.1, 0.0), vec3(0.0, 0.1, -0.15), 0.0, -0.1), // left arm
    LegKeyframe(vec3(1.25, 0.3, -0.3), vec3(0.0, 0.0, 0.0), vec3(-0.8, 0.0, 0.0), vec3(0.3, 0.0, 0.0), 0.0), // right leg
    LegKeyframe(vec3(0.1, 0.3, 0.1), vec3(-0.1, 0.2, -0.1), vec3(-0.2, 0.0, 0.0), vec3(-0.2, 0.0, 0.0), 0.0), // left leg
    TailKeyframe(vec3(0.2, -0.3, 0.0), vec3(-0.1, 0.0, -0.6), 1.0)); // tail

void setPose(Keyframe keyframe)
{
    #define set_vars(angle) s = sin(angle); c = cos(angle)
    #define set_qx(target, angle)   set_vars(angle); target = vec4(s.x, 0.0, 0.0, c.x)
    #define set_qy(target, angle)   set_vars(angle); target = vec4(0.0, s.y, 0.0, c.y)
    #define set_qz(target, angle)   set_vars(angle); target = vec4(0.0, 0.0, s.z, c.z)
    #define set_qxy(target, angle)  set_vars(angle); target = vec4(s.x * c.y, c.x * s.y, s.x * s.y, c.x * c.y)
    #define set_qxz(target, angle)  set_vars(angle); target = vec4(s.x * c.z,  - s.x * s.z, c.x * s.z, c.x * c.z)
    #define set_qyx(target, angle)  set_vars(angle); target = vec4(s.x * c.y, c.x * s.y,  - s.x * s.y, c.x * c.y)
    #define set_qyz(target, angle)  set_vars(angle); target = vec4(s.y * s.z, s.y * c.z, c.y * s.z, c.y * c.z)
    #define set_qzx(target, angle)  set_vars(angle); target = vec4(s.x * c.z, s.x * s.z, c.x * s.z, c.x * c.z)
    #define set_qzy(target, angle)  set_vars(angle); target = vec4(-s.y * s.z, s.y * c.z, c.y * s.z, c.y * c.z)
    #define set_qxyz(target, angle) set_vars(angle); target = vec4((s.x * c.y * c.z + c.x * s.y * s.z), (c.x * s.y * c.z - s.x * c.y * s.z), (c.x * c.y * s.z + s.x * s.y * c.z), (c.x * c.y * c.z - s.x * s.y * s.z))
    #define set_qxzy(target, angle) set_vars(angle); target = vec4((s.x * c.y * c.z - c.x * s.y * s.z), (c.x * s.y * c.z - s.x * c.y * s.z), (c.x * c.y * s.z + s.x * s.y * c.z), (c.x * c.y * c.z + s.x * s.y * s.z))
    #define set_qyxz(target, angle) set_vars(angle); target = vec4((s.x * c.y * c.z + c.x * s.y * s.z), (c.x * s.y * c.z - s.x * c.y * s.z), (c.x * c.y * s.z - s.x * s.y * c.z), (c.x * c.y * c.z + s.x * s.y * s.z))
    #define set_qyzx(target, angle) set_vars(angle); target = vec4((s.x * c.y * c.z + c.x * s.y * s.z), (c.x * s.y * c.z + s.x * c.y * s.z), (c.x * c.y * s.z - s.x * s.y * c.z), (c.x * c.y * c.z - s.x * s.y * s.z))
    #define set_qzxy(target, angle) set_vars(angle); target = vec4((s.x * c.y * c.z - c.x * s.y * s.z), (c.x * s.y * c.z + s.x * c.y * s.z), (c.x * c.y * s.z + s.x * s.y * c.z), (c.x * c.y * c.z - s.x * s.y * s.z))
    #define set_qzyx(target, angle) set_vars(angle); target = vec4((s.x * c.y * c.z - c.x * s.y * s.z), (c.x * s.y * c.z + s.x * c.y * s.z), (c.x * c.y * s.z - s.x * s.y * c.z), (c.x * c.y * c.z + s.x * s.y * s.z))

    vec3 s, c;

    pose.offset = keyframe.offset;
    set_qxyz(pose.rotation, keyframe.rotation);
    set_qxyz(pose.bodyCurve, keyframe.bodyCurve);

    set_qzxy(pose.head.rotation, keyframe.head.rotation);
    pose.head.eyesDirection = keyframe.head.eyesDirection;
    set_qzxy(pose.head.earsRotation, keyframe.head.earsRotation);
    pose.head.eyesOpen = keyframe.head.eyesOpen;
    pose.head.eyelidsOffset = keyframe.head.eyelidsOffset;
    pose.head.eyebrowsHeight = keyframe.head.eyebrowsHeight;
    pose.head.cheeksHeight = keyframe.head.cheeksHeight;
    pose.head.cheeksBlush = keyframe.head.cheeksBlush;
    pose.head.mouthHeight = keyframe.head.mouthHeight;
    pose.head.mouthOpen = keyframe.head.mouthOpen;

    set_qxyz(pose.rightArm.shoulderRotation, keyframe.rightArm.shoulderRotation);
    set_qxyz(pose.rightArm.armRotation, keyframe.rightArm.armRotation);
    set_qy(pose.rightArm.elbowRotation, keyframe.rightArm.elbowRotation);
    set_qxyz(pose.rightArm.wristRotation, keyframe.rightArm.wristRotation);
    pose.rightArm.fingersSpread = keyframe.rightArm.fingersSpread;
    pose.rightArm.fingersFold = keyframe.rightArm.fingersFold;

    set_qxyz(pose.leftArm.shoulderRotation, keyframe.leftArm.shoulderRotation);
    set_qxyz(pose.leftArm.armRotation, keyframe.leftArm.armRotation);
    set_qy(pose.leftArm.elbowRotation, keyframe.leftArm.elbowRotation);
    set_qxyz(pose.leftArm.wristRotation, keyframe.leftArm.wristRotation);
    pose.leftArm.fingersSpread = keyframe.leftArm.fingersSpread;
    pose.leftArm.fingersFold = keyframe.leftArm.fingersFold;

    set_qxyz(pose.rightLeg.baseRotation, keyframe.rightLeg.baseRotation);
    set_qxyz(pose.rightLeg.rotation, keyframe.rightLeg.rotation);
    set_qx(pose.rightLeg.kneeRotation, keyframe.rightLeg.kneeRotation);
    set_qxyz(pose.rightLeg.footRotation, keyframe.rightLeg.footRotation);
    pose.rightLeg.toesAngle = keyframe.rightLeg.toesAngle;

    set_qxyz(pose.leftLeg.baseRotation, keyframe.leftLeg.baseRotation);
    set_qxyz(pose.leftLeg.rotation, keyframe.leftLeg.rotation);
    set_qx(pose.leftLeg.kneeRotation, keyframe.leftLeg.kneeRotation);
    set_qxyz(pose.leftLeg.footRotation, keyframe.leftLeg.footRotation);
    pose.leftLeg.toesAngle = keyframe.leftLeg.toesAngle;

    set_qxyz(pose.tail.baseRotation, vec3(clamp(keyframe.tail.baseRotation.x, -0.5, 0.2), keyframe.tail.baseRotation.yz));
    set_qxyz(pose.tail.rotation, vec3(clamp(keyframe.tail.rotation.x, -0.5, 0.2), keyframe.tail.rotation.yz));
    pose.tail.curve = clamp(keyframe.tail.curve, -1.5, 1.5);
}

Keyframe mixKeyframe(Keyframe keyframe1, Keyframe keyframe2, float f)
{
    #define mixProperty(property) mix(keyframe1.property, keyframe2.property, f)

    Keyframe keyframe;

    keyframe.offset = mixProperty(offset);
    keyframe.rotation = mixProperty(rotation);
    keyframe.bodyCurve = mixProperty(bodyCurve);

    keyframe.head.rotation = mixProperty(head.rotation);
    keyframe.head.eyesDirection = mixProperty(head.eyesDirection);
    keyframe.head.eyesOpen = mixProperty(head.eyesOpen);
    keyframe.head.earsRotation = mixProperty(head.earsRotation);
    keyframe.head.eyelidsOffset = mixProperty(head.eyelidsOffset);
    keyframe.head.cheeksHeight = mixProperty(head.cheeksHeight);
    keyframe.head.cheeksBlush = mixProperty(head.cheeksBlush);
    keyframe.head.mouthHeight = mixProperty(head.mouthHeight);
    keyframe.head.mouthOpen = mixProperty(head.mouthOpen);

    keyframe.rightArm.shoulderRotation = mixProperty(rightArm.shoulderRotation);
    keyframe.rightArm.armRotation = mixProperty(rightArm.armRotation);
    keyframe.rightArm.elbowRotation = mixProperty(rightArm.elbowRotation);
    keyframe.rightArm.wristRotation = mixProperty(rightArm.wristRotation);
    keyframe.rightArm.fingersSpread = mixProperty(rightArm.fingersSpread);
    keyframe.rightArm.fingersFold = mixProperty(rightArm.fingersFold);

    keyframe.leftArm.shoulderRotation = mixProperty(leftArm.shoulderRotation);
    keyframe.leftArm.armRotation = mixProperty(leftArm.armRotation);
    keyframe.leftArm.elbowRotation = mixProperty(leftArm.elbowRotation);
    keyframe.leftArm.wristRotation = mixProperty(leftArm.wristRotation);
    keyframe.leftArm.fingersSpread = mixProperty(leftArm.fingersSpread);
    keyframe.leftArm.fingersFold = mixProperty(leftArm.fingersFold);

    keyframe.rightLeg.baseRotation = mixProperty(rightLeg.baseRotation);
    keyframe.rightLeg.rotation = mixProperty(rightLeg.rotation);
    keyframe.rightLeg.kneeRotation = mixProperty(rightLeg.kneeRotation);
    keyframe.rightLeg.footRotation = mixProperty(rightLeg.footRotation);
    keyframe.rightLeg.toesAngle = mixProperty(rightLeg.toesAngle);

    keyframe.leftLeg.baseRotation = mixProperty(leftLeg.baseRotation);
    keyframe.leftLeg.rotation = mixProperty(leftLeg.rotation);
    keyframe.leftLeg.kneeRotation = mixProperty(leftLeg.kneeRotation);
    keyframe.leftLeg.footRotation = mixProperty(leftLeg.footRotation);
    keyframe.leftLeg.toesAngle = mixProperty(leftLeg.toesAngle);

    keyframe.tail.baseRotation = mixProperty(tail.baseRotation);
    keyframe.tail.rotation = mixProperty(tail.rotation);
    keyframe.tail.curve = mixProperty(tail.curve);

    return keyframe;
}

Keyframe mirrorKeyframe(Keyframe keyframe)
{
    #define mirror_vec3(a) a = vec3(a.x, -a.yz)
    #define switch_vec3(a, b) c = a; a = b; b = c
    #define switch_float(a, b) d = a; a = b; b = d
    vec3 c;
    float d;

    mirror_vec3(keyframe.rotation);
    mirror_vec3(keyframe.bodyCurve);
    mirror_vec3(keyframe.head.rotation);
    mirror_vec3(keyframe.tail.baseRotation);
    mirror_vec3(keyframe.tail.rotation);
    switch_vec3(keyframe.rightArm.shoulderRotation, keyframe.leftArm.shoulderRotation);
    switch_vec3(keyframe.rightArm.armRotation, keyframe.leftArm.armRotation);
    switch_vec3(keyframe.rightArm.elbowRotation, keyframe.leftArm.elbowRotation);
    switch_vec3(keyframe.rightArm.wristRotation, keyframe.leftArm.wristRotation);
    switch_float(keyframe.rightArm.fingersSpread, keyframe.leftArm.fingersSpread);
    switch_float(keyframe.rightArm.fingersFold, keyframe.leftArm.fingersFold);
    switch_vec3(keyframe.rightLeg.baseRotation, keyframe.leftLeg.baseRotation);
    switch_vec3(keyframe.rightLeg.rotation, keyframe.leftLeg.rotation);
    switch_vec3(keyframe.rightLeg.kneeRotation, keyframe.leftLeg.kneeRotation);
    switch_vec3(keyframe.rightLeg.footRotation, keyframe.leftLeg.footRotation);
    switch_float(keyframe.rightLeg.toesAngle, keyframe.leftLeg.toesAngle);

    return keyframe;
}

vec4 sdEye(vec3 pos, float side)
{
    float bounds = sdBoxApprox(pos, vec3(0.05));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    const float s1 = 0.038; // eyeball size
    const float s2 = s1 * 0.45; // pupil size
    const float s3 = s1 + 0.002; // eye lids size
    const float y1 = 0.6 * s3; // eye lids opening

    vec3 pos1 = pos;

    float d1 = sdSphere(pos1, s3); // eyelids

    vec3 pos2 = pos1;
    pos2.y -= y1; // opening start
    pos2.yz *= rotation(pose.head.eyelidsOffset);

    vec3 pos3 = pos2;
    pos3.yz *= rotation(PI05 - pose.head.eyesOpen * (PI05 + pose.head.eyelidsOffset));
    float d2 = smax(d1, pos3.y, pose.head.eyesOpen * 0.02); // upper eyelid

    pos3 = pos2;
    pos3.yz *= rotation(-PI05 + pose.head.eyesOpen * (PI05 - pose.head.eyelidsOffset));
    float d3 = smax(d1, pos3.y, pose.head.eyesOpen * 0.02); // lower eyelid

    d1 = min(d2, d3);

    float edge = 0.5 * (sign(pos2.z) + 3.0);
    vec4 dm1 = vec4(d1, MATERIAL_SKIN, edge, 0.03);

    pos2 = pos1;
    d1 = sdSphere(pos2, s1); // eyeball

    pos2.xy *= rotation(0.1 - side * pose.head.eyesDirection.x);
    pos2.yz *= rotation(pose.head.eyesDirection.y);

    pos2.y -= s1;
    d2 = sdSphere(pos2, s2); // pupil

    vec4 dm2 = vec4(d1, d2 > 0.0 ? MATERIAL_EYE : MATERIAL_PUPIL, 0.0, 0.0);
    dm1 = smin(dm1, dm2);

    return dm1;
}

vec4 sdEar(vec3 pos)
{
    float bounds = sdBoxApprox(pos, vec3(0.055), vec3(0.0, 1.0, -0.5));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    float d1, d2;

    vec3 pos1 = pos;
    pos1.y += 0.1;
    d1 = sdEllipsoid(pos1, vec3(0.05, 0.2, 0.06));

    pos1.y -= 0.11;
    pos1.z += 0.18;
    d2 = sdSphere(pos1, 0.2);
    d1 = smax(d1, d2, 0.02);

    pos1 = pos;
    pos1.z -= 0.02;
    pos1.y -= 0.04;
    d2 = sdEllipsoid(pos1, vec3(0.02, 0.06, 0.02));
    d1 = smax(d1, -d2, 0.02);

    d1 = smax(d1, -pos.y - 0.05, 0.1);

    float hue = d2 < 0.001 ? 1.0 : 0.0;
    float edge = d2 < 0.001 ? 2.0 : 1.0;
    float merge = 0.005 + 0.01 * smoothstep(-0.03, 0.03, d2);

    return vec4(d1, MATERIAL_SKIN, edge + 0.99 * hue, merge);
}

vec4 sdHead(vec3 pos)
{
    const vec4 eyesRotation = vec4(0.128, 0.093, 0.145, 0.977);
    const float blushSize = 0.02;
    const float blushMargin = 0.03;

    float bounds = sdBoxApprox(pos, vec3(0.8, 0.25, 0.3), vec3(0.0, -0.2, 0.5));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    vec3 pos1, pos2;
    float d1, d2, d3;

    pos.z -= 0.05;
    pos.yz *= rotation_60;

    pos1 = pos;
    pos1.xz *= rotation_90;
    pos1.xy *= rotation_n90;
    d1 = sdArc(pos1, 0.18, -0.4, 0.14, -0.11); // head arc
    pos1.y -= 0.02;
    d2 = sdSphere(pos1, 0.144);
    d1 = smin(d1, d2, 0.01); // smooth arc

    pos1 = pos;
    float rcurve = 0.3;
    pos1 -= vec3(0.0, 0.22 - rcurve, 0.07);
    d2 = sdCircle(pos1.xy, rcurve); // flatten head arc top
    d2 = length(vec2(d2, pos1.z)) - 0.055;

    d1 = smax(d1, -d2, 0.22);
    //d1 = min(d1, d2);
    float merge = smoothstep(0.15, -0.05, pos1.z) * 0.15 + 0.0005;

    // eyes
    vec3 eyesPos = pos;
    float eyeSide = sign(eyesPos.x);
    eyesPos.x = abs(eyesPos.x);
    eyesPos -= vec3(0.053, 0.085, 0.081);
    eyesPos = rotate(eyesPos, eyesRotation);

    pos1 = eyesPos;
    pos1 -= vec3(0.0, 0.02, -0.005);
    d2 = sdSphere(pos1, 0.035); // eyes socket
    d1 = smax(d1, -d2, 0.04);

    // eyes top outline group
    pos1 = eyesPos;
    pos1 -= vec3(0.004, 0.03, -0.015);
    d2 = sdSphere(pos1, 0.025);

    float edge = d2 < 0.0 ? 3.0 : 0.0; // eyes top outline

    // eyebrows
    pos1 = pos;
    pos1.x = abs(pos1.x);
    pos1.yz *= rotation(0.15 - pose.head.eyebrowsHeight * 0.35);
    pos1.xy *= rotation_n30;

    pos2 = pos1;
    pos2.z += 0.025;
    d2 = sdCircle(pos2.xz, 0.025); // eyebrow size
    d2 = max(d2, -pos2.y);

    pos2 = pos1;
    pos2.z -= 0.05;
    pos2.x += 0.03; // eyebrow angle
    d3 = sdCircle(pos2.xz, 0.08); // eyebrow curve
    d3 = max(d3, -pos2.y);

    edge = d2 > 0.0 ? edge :
           d3 > 0.0 ? 1.0 : 3.0;

    vec4 dm1 = vec4(d1, MATERIAL_SKIN, edge, merge);

    pos1 = eyesPos;
    vec4 dm2 = sdEye(pos1, eyeSide);
    dm1 = smin(dm1, dm2);

    pos1 = pos;
    pos1.yz *= rotation_n45;
    pos1.x = abs(pos1.x);
    pos1.xy *= rotation_n15;
    pos1 -= vec3(0.04, 0.09, -0.01);
    pos1.xz *= rotation_n15;
    pos1 = rotate(pos1, pose.head.earsRotation);
    pos1.y -= 0.02;
    dm2 = sdEar(pos1);
    dm1 = smin(dm1, dm2);

    // mouth
    pos1 = pos;
    pos1 += vec3(0.0, 0.06 + pose.head.mouthHeight, -0.25 + pose.head.mouthHeight);
    d1 = sdEllipsoid(pos1, vec3(0.03, 0.02, 0.015) * clamp(pose.head.mouthOpen, 0.001, 4.0));
    dm1.xyz = maxx(dm1.xyz, vec3(-d1, MATERIAL_MOUTH, 0.0));

    // cheeks
    float f = clamp(pose.head.cheeksHeight, 0.0, 1.0);
    pos1 = pos;
    pos1.x = abs(pos1.x);
    pos1 -= vec3(0.055, 0.06, 0.15);
    d1 = sdSphere(pos1, 0.07 + 0.015 * clamp(f, 0.0, 1.0));
    dm2 = vec4(d1, MATERIAL_SKIN, 0.0, 0.01);
    dm1 = smin(dm1, dm2);

    // cheeks blush
    pos1 = pos;
    pos1.x = abs(pos1.x);
    pos1 -= vec3(0.1, 0.12, 0.12);
    d1 = sdSphere(pos1, blushSize);

    float hue = clamp(pose.head.cheeksBlush * (blushMargin - d1) / blushMargin, 0.0, 1.0);
    hue = abs(dm1.y - MATERIAL_SKIN) < 0.001 ? hue : 0.0;
    dm1.z += 0.99 * hue;

    return dm1;
}


vec4 sdLeg(vec3 pos, vec4 legRotation, vec4 kneeRotation, vec4 footRotation, float toesAngle)
{
    const float l1 = 0.1; // thigh length
    const float l2 = 0.07; // shin length
    const float l3 = 0.075; // foot length

    const float t1 = 0.085; // thigh thickness
    const float t2 = 0.065; // shin thickness
    const float h3 = 0.04; // foot height
    const float w3 = 0.065; // foot width

    vec3 pos1 = pos;
    pos1.y += l1 + 0.04;
    pos1 = rotate(pos1, legRotation);

    float bounds = sdBoxApprox(pos1, vec3(0.1, 0.2, 0.1), vec3(0.0, -0.6, -0.2));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    float d1 = sdEllipsoid(pos1, vec3(t1, l1, t1)); // thigh
    float merge = smoothstep(-0.6, 0.1, pos1.y / l1);

    vec4 dm1 = vec4(d1, MATERIAL_SKIN, 0.0, 0.2 * merge);
    pos1.y += l1 - t2 * 0.8;
    pos1 = rotate(pos1, kneeRotation);
    pos1.y += l2 - t2 * 0.5;

    d1 = sdEllipsoid(pos1, vec3(t2, l2, t2)); // shin
    merge = smoothstep(-0.8, 0.0, pos1.y / l2);
    vec4 dm2 = vec4(d1, MATERIAL_SKIN, 0.0, 0.1 * merge);

    pos1.y += l2 - t2 * 0.8;
    pos1 = rotate(pos1, footRotation);
    pos1.y += t2 * 0.8;
    pos1.z -= l3 * 0.4;

    pos1.yz = bendSpace(pos1.yz, vec2(-0.4 * h3, -0.2 * l3), 1.0, 0.5, toesAngle);

    merge = smoothstep(0.5, -0.1, pos1.z / l3);
    float d2 = sdEllipsoid(pos1, vec3(w3, h3, l3)); // foot

    pos1.y += 0.4;
    float d3 = sdSphere(pos1, 0.385); // flatten foot curve
    d2 = smax(d2, -d3, 0.01);

    vec4 dm3 = vec4(d2, MATERIAL_SKIN, 0.0, 0.04 * merge);
    dm2 = smin(dm2, dm3, dm3.w);

    dm1 = smin(dm1, dm2, dm2.w);
    return dm1;
}

vec4 sdFinger(vec3 pos, mat2 rotation)
{
    float bounds = sdBoxApprox(pos, vec3(0.02, 0.01, 0.01), vec3x(-0.1));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    vec3 pos1 = pos;

    float d = sdEllipsoid(pos1, vec3(0.015, 0.009, 0.009)); // finger
    float merge = smoothstep(-0.015, 0.0, pos1.x);
    vec4 dm1 = vec4(d, MATERIAL_SKIN, 0.0, 0.005 * merge);

    pos1.x += 0.011;
    pos1.xz *= rotation;
    pos1.x += 0.001;
    d = sdEllipsoid(pos1, vec3(0.01, 0.007, 0.007)); // finger tip
    merge = smoothstep(-0.01, 0.0, pos1.x);

    vec4 dm2 = vec4(d, MATERIAL_SKIN, 0.0, 0.005 * merge);

    dm1 = smin(dm1, dm2);

    return dm1;
}

vec4 sdFingers(vec3 pos, float spread, float fold)
{
    const float x = 0.006;
    const float r1 = 0.035 - x;
    const float r2 = 0.005 + x;

    float bounds = sdBoxApprox(pos, vec3(0.05), vec3x(-0.5));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    float spreadAngle = 0.2 * clamp(spread, -1.0, 1.0);
    float foldAngle = -PI05 * clamp(fold, -1.0, 1.0);

    vec3 pos1, pos2;
    vec4 dm1, dm2;

    mat2 m1 = rotation(-0.4 - spreadAngle);
    mat2 m2 = rotation(spreadAngle * 0.5);
    mat2 m3 = rotation(foldAngle);
    mat2 m4 = rotation(foldAngle * 0.5);

    pos1 = pos;
    pos1 += vec3(0.005, -0.006, 0.005);

    float side = sign(pos1.y);
    pos1.y = abs(pos1.y);

    // middle
    pos2 = pos1;
    pos2.x += r1;
    pos2.xz *= m3;
    pos2.x += r2;
    dm1 = sdFinger(pos2, m4);

    // index and ring
    pos1.xy *= m1;
    pos2 = pos1;
    pos2.x += r1;
    pos2.xy *= rotation_7_5;
    pos2.xz *= m3;
    pos2.x += r2;
    pos2.xy *= m2;
    dm2 = sdFinger(pos2, m4);
    dm1 = minx(dm1, dm2);

    // thumb and pinky
    pos1.xy *= m1;
    pos1.xy = side > 0.0 ? pos1.xy * m1 : pos1.xy; // thumb gap
    pos1.x -= 0.004 * side; // thumb length
    pos2 = pos1;
    pos2.x += r1;
    pos2.xy *= rotation_15;
    pos2.xz *= m3;
    pos2.x += r2;
    pos2.xy *= m2;
    dm2 = sdFinger(pos2, m4);
    dm1 = minx(dm1, dm2);

    return dm1;

}

vec4 sdArm(vec3 pos, vec4 armRotation, vec4 elbowRotation, vec4 wristRotation, float fingersSpread, float fingersFold)
{
    const float l1 = 0.11; // upper arm length
    const float l2 = 0.07; // forearm length

    const float t1 = 0.07; // upper arm thickness
    const float t2 = 0.05; // forearm thickness

    const vec3 s3 = vec3(0.035, 0.04, 0.025);

    vec3 pos1 = pos;
    pos1 = rotate(pos1, armRotation);

    float bounds = sdBoxApprox(pos, vec3(0.2), vec3x(-0.5));
    if (bounds > BOUNDS_MARGIN)
    {
       return vec4(bounds, 0.0, 0.0, 0.0);
    }

    pos1.x += l1 - t1;
    float d1 = sdEllipsoid(pos1, vec3(l1, t1, t1)); // upper arm
    float merge = smoothstep(-0.3 * l1, 0.5 * l1, pos1.x);
    vec4 dm1 = vec4(d1, MATERIAL_SKIN, 0.0, 0.05 * merge);

    pos1.x += l1 - t2;
    pos1 = rotate(pos1, elbowRotation);
    pos1.x += l2 - 0.5 * t2;

    d1 = sdEllipsoid(pos1, vec3(l2, t2, t2)); // forearm
    merge = smoothstep(-0.5 * l2, 0.5 * l2, pos1.x);
    vec4 dm2 = vec4(d1, MATERIAL_SKIN, 0.0, 0.05 * merge);
    dm1 = smin(dm1, dm2);

    pos1.x += l2 - 0.5 * t2;
    pos1 = rotate(pos1, wristRotation);
    pos1.x += t2 - 0.8 * s3.z;
    pos1.z += 0.5 * s3.z;

    d1 = sdEllipsoid(pos1, s3); // palm
    merge = smoothstep(-s3.x, 0.5 * s3.x, pos1.x);
    dm2 = vec4(d1, MATERIAL_SKIN, 0.0, 0.05 * merge);
    dm1 = smin(dm1, dm2);

    pos1.x -= 0.01;
    dm2 = sdFingers(pos1, fingersSpread, fingersFold);
    dm1 = smin(dm1, dm2);

    return dm1;
}

vec4 sdTail(vec3 pos, float curve)
{
    // length
    const float l1 = 0.4;
    const float l2 = 0.1;

    // thickness
    const float t1 = 0.02;
    const float t2 = 0.04;

    float bounds = sdBoxApprox(pos, vec3(0.1, 0.4, 0.3), vec3z(-1.0));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec4(bounds, 0.0, 0.0, 0.0);
    }

    vec3 pos1 = pos;

    pos1 = vec3(pos1.y, -pos1.z, pos1.x);
    float d1 = sdArc(pos1, l1, curve, t1, 0.03);

    float merge = 0.05 * smoothstep(l1 * 0.5, 0.0, length(pos));
    vec4 dm1 = vec4(d1, MATERIAL_SKIN, 0.0, merge);

    pos1.xy *= rotation(-curve);
    pos1.y -= 1.0 * l1 * cos(curve * 0.5);
    pos1.xy *= rotation(-curve);
    d1 = sdArc(pos1, l2, 0.4 * curve, t2, 0.4);

    vec4 dm2 = vec4(d1, MATERIAL_SKIN, 0.0, merge);
    dm1 = smin(dm1, dm2, 0.02);

    return dm1;
}

vec3 sdMoomin(vec3 pos)
{
    float d1, d2, d3;
    vec4 d4, d5;
    vec3 pos1, pos2;
    vec3 d = vec3(MAX_DIST, 0.0, 0.0);

    pos -= pose.offset;
    pos = rotate(pos, pose.rotation);

    float bounds = sdBoxApprox(pos, vec3(0.5, 0.6, 0.5), vec3(0.0, 0.9, -0.3));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec3(bounds, 0.0, 0.0);
    }

    d = vec3(MAX_DIST, 0.0, 0.0);

    // body
    pos1 = pos;
    pos1 = rotate(pos1, quaternionInverse(pose.bodyCurve));
    pos1.y -= 0.05;
    pos1 = rotate(pos1, pose.bodyCurve);
    pos1.y -= 0.32;
    d1 = sdSphere(pos1, 0.22); // belly

    vec3 tailPos = pos1;
    vec3 legsPos = pos1;
    legsPos.y += 0.01;
    legsPos.z += 0.03;

    pos1.y -= 0.18;
    pos1 = rotate(pos1, pose.bodyCurve);
    pos1.y -= 0.1;

    vec3 armsPos = pos1;
    armsPos.y += 0.08;

    d2 = sdEllipsoid(pos1, vec3(0.12, 0.25, 0.12)); // ribcage
    d1 = smin(d1, d2, 0.3);

    d = minx(d, vec3(d1, MATERIAL_SKIN, 0.0));

    // head
    pos1.y -= 0.11;
    pos1 = rotate(pos1, pose.bodyCurve);
    pos1 = rotate(pos1, pose.head.rotation);
    pos1.y -= 0.1;
    d = smin(d, sdHead(pos1));

    // arms
    pos1 = armsPos;
    pos1 = rotate(pos1, pose.rightArm.shoulderRotation);
    pos1.x += 0.15;
    d4 = sdArm(pos1, pose.rightArm.armRotation, pose.rightArm.elbowRotation, pose.rightArm.wristRotation, pose.rightArm.fingersSpread, pose.rightArm.fingersFold);

    pos1 = armsPos;
    pos1.x = -pos1.x;
    pos1 = rotate(pos1, pose.leftArm.shoulderRotation);
    pos1.x += 0.15;
    d5 = sdArm(pos1, pose.leftArm.armRotation, pose.leftArm.elbowRotation, pose.leftArm.wristRotation, pose.leftArm.fingersSpread, pose.leftArm.fingersFold);

    d = smin(d, minx(d4, d5));

    // legs
    pos1 = legsPos;
    pos1.x += 0.08;
    pos1.z -= 0.06;
    pos1 = rotate(pos1, pose.rightLeg.baseRotation);
    pos1.z += 0.06;
    d4 = sdLeg(pos1, pose.rightLeg.rotation, pose.rightLeg.kneeRotation, pose.rightLeg.footRotation, pose.rightLeg.toesAngle);

    pos1 = legsPos;
    pos1.x = -pos1.x;
    pos1.x += 0.08;
    pos1.z -= 0.06;
    pos1 = rotate(pos1, pose.leftLeg.baseRotation);
    pos1.z += 0.06;
    d5 = sdLeg(pos1, pose.leftLeg.rotation, pose.leftLeg.kneeRotation, pose.leftLeg.footRotation, pose.leftLeg.toesAngle);

    d = smin(d, minx(d4, d5));

    pos1 = tailPos;
    pos1 = rotate(pos1, pose.tail.baseRotation);
    pos1.y += 0.08;
    pos1.z += 0.1;
    pos1.yz *= rotation_n60;
    pos1 = rotate(pos1, pose.tail.rotation);
    pos1.z += 0.05;
    d4 = sdTail(pos1, pose.tail.curve);
    d = smin(d, d4);

    return d;
}

// --- ------ ---

float getGroundHeight(vec3 pos)
{
    return 0.5 * (sin(0.15 * pos.x) + sin(0.25 * pos.z));
}

vec3 getWindForce(vec3 pos, float time)
{
    float phase = pos.x + pos.z; // phase direction
    float an = 4.0; // force direction

    phase += 0.2 * (sin(2.0 * pos.x + time) + sin(3.0 * pos.z + time)); // noise

    phase = sin(1.5 * time + phase);
    an += phase; // change direction

    float stength = 0.1 + 2.0 * map11_01(phase);
    stength *= 0.6 + 0.4 * sin(0.2 * pos.z + 0.5 * time); // pulse

    return stength * vec3(cos(an), 0.0, sin(an));
}

vec3 sdRock(vec3 pos, float size, float h1, float h2)
{
    size *= 1.0 - 0.5 * h2;

    float bounds = sdBoxApprox(pos, vec3(1.5 * size));
    if (bounds > BOUNDS_MARGIN)
    {
        return vec3(bounds, 0.0, 0.0);
    }

    float phase = PI * h2;

    vec3 pos1 = pos;
    pos1.x += 0.02 * (sin(15.0 * pos.x + phase) + sin(10.0 * pos.z + phase));
    pos1.y += 0.01 * (sin(13.0 * pos.x + phase) + sin(18.0 * pos.z + phase));
    pos1.z += 0.02 * (sin(10.0 * pos.x + phase) + sin(15.0 * pos.z + phase));
    pos1.y += 0.4 * size;

    pos1 /= size;
    float d = sdSphere(pos1, 1.0);
    d *= size;

    return vec3(d, MATERIAL_ROCK, 0.0);
}

vec3 sdRocks(vec3 pos)
{
    const vec2 gridSize = vec2(15.0);
    const float size1 = 0.5;
    const float size2 = 0.7;

    vec3 pos1 = pos;
    vec2 index = floor(pos1.xz / gridSize + 0.5);
    pos1.xz -= index * gridSize;

    float h1 = hash(index);
    float h2 = hash(index + 1000.0);
    float size = mix(size1, size2, fract(100.0 * (h1 + h2)));

    pos1.xz -= (0.5 * gridSize - size) * vec2(map01_11(h1), map01_11(h2));

    return sdRock(pos1, size, h1, h2);
}

vec3 sdFlower(vec3 pos, float hue, float scale, vec3 dir)
{
    const float size1 = 0.02; // petals
    const float thickness1 = 0.002;
    const float size2 = 0.03; // base
    const float size3 = 0.02; // disk
    const float size4 = 0.2; // stem
    const float thickness4 = 0.004;

    pos /= scale;

    float bounds = sdBoxApprox(pos, vec3(0.07, 0.1, 0.07), vec3y1) * scale;
    if (bounds > BOUNDS_MARGIN)
    {
        return vec3(bounds, 0.0, 0.0);
    }

    pos.zy *= rotation(atan(-dir.z, dir.y));
    pos.xy *= rotation(atan(-dir.x, dir.y));

    pos.y -= 0.8 * size4;

    // petals
    vec3 pos1 = pos;
    pos1.xy *= rotation_n30;

    float index = 0.0;
    vec3 pos2 = pos1;
    pos2.xz = radialMod(pos2.xz, 5.0, index);
    pos2.x -= 1.5 * size1;
    pos2.xy *= rotation_30;
    float d = sdCircle(pos2.xz, size1);
    d = max(0.0, d);
    d = length(vec2(d, pos2.y));
    d -= thickness1;
    vec3 d1 = vec3(d, MATERIAL_FLOWER1, hue);

    // base
    pos2 = pos1;
    pos2.y -= 0.4 * size2;
    d = sdSphere(pos2, size2);
    d = max(d, pos2.y + 0.68 * size2);
    vec3 d2 = vec3(d, MATERIAL_GRASS, 0.8);
    d1 = smin(d1, d2, 0.01);

    // stem
    pos2 = pos;
    pos2.x -= 0.73 * size4;
    pos2.y += 0.7 * size4;
    d = sdCircle(pos2.xy, size4);
    d = length(vec2(d, pos2.z));
    d = max(d, pos2.x);
    d = max(d, pos1.y + 0.1 * size4);
    d = max(d, -pos2.y);
    d -= thickness4;
    d2 = vec3(d, MATERIAL_GRASS, 0.5);
    d1 = smin(d1, d2, 0.01);

    // disk
    pos2 = pos1;
    pos2.y += size3;
    d = sdSphere(pos2, size3);
    d = max(d, -pos2.y + 0.5 * size3);
    d2 = vec3(d, MATERIAL_FLOWER2, 0.0);
    d1 = minx(d1, d2);

    d1.x *= scale;
    return d1;
}

vec3 sdFlowers(vec3 pos, float time)
{
    const vec2 gridSize = vec2(1.5);

    float bounds = pos.y - 0.4;
    if (bounds > BOUNDS_MARGIN)
    {
        return vec3(bounds, 0.0, 0.0);
    }

    float viewDist = length(state.origin - pos);
    if (viewDist > 30.0)
    {
        return vec3(MAX_DIST, 0.0, 0.0);
    }

    vec3 pos1 = pos;

    float h = 0.35 + 0.05 * (sin(pos.x) + sin(pos.z)); // height

    vec3 dir = vec3y1;
    dir += 0.3 * getWindForce(pos, time + 0.2);
    dir.y = max(0.0, dir.y);
    dir = normalize(dir);
    dir *= h / dir.y;

    float y = clamp(pos1.y / dir.y, 0.0, 1.0);

    vec2 index = floor((pos1.xz - y * dir.xz) / gridSize + 0.5);

    float rocksDist = sdRocks(vec3(index * gridSize, 0.0).xzy).x;
    if (rocksDist < 0.2)
    {
        return vec3(MAX_DIST, 0.0, 0.0);
    }

    vec3 pos2 = pos1;
    pos2.xz -= index * gridSize;
    pos2.xz -= 0.1 * y * dir.xz; // skew

    float h1 = hash(index);
    float h2 = hash(index + 1000.0);
    float h3 = fract(h1 + h2);

    pos2.xz -= (0.4 * gridSize - 0.1) * map01_11(vec2(h1, h2)); // jitter

    return sdFlower(pos2, h1, h / 0.25, dir);
}

float getGrassShade(vec2 pos)
{
    pos.x += 4.0 * fbm(pos);
    float x = 0.99 * fbm(pos * vec2(1.0, 0.8) * 0.3);
    x = x * x;
    x = x * (2.0 - x);
    return x;
}

vec3 sdGrass(vec3 pos, float time)
{
    const vec2 gridSize1 = vec2(0.05);
    const vec2 gridSize2 = vec2(0.15);
    const float h1 = 0.08;
    const float h2 = 0.15;
    const float h3 = 0.03;
    const float r1 = 0.005;
    const float r2 = 0.015;
    const float rocksMargin = 0.0;
    const vec2[] offsets = vec2[](vec2(0.0), vec2(0.2, 0.8), vec2(0.7, 0.3));

    float bounds = pos.y - h1 - 2.0 * h3;
    if (bounds > BOUNDS_MARGIN)
    {
        return vec3(bounds, 0.0, 0.0);
    }

    float viewDist = length(state.origin - pos);

    float d1 = pos.y;
    vec2 rootPos = pos.xz;

    if (viewDist > 20.0)
    {
        d1 = pos.y - 0.5 * (h1 + h2);
    }
    else
    {
        float rocksDist = sdRocks(vec3(pos.xz, 0.0).xzy).x - rocksMargin;
        float rocksMask1 = smoothstep(0.0, 0.3, rocksDist); // skew
        float rocksMask2 = smoothstep(-0.1, 0.2, rocksDist); // height

        for (int i = 0; i < 3; i++)
        {
            float j = float(i);

            vec3 pos1 = pos;
            vec2 gridSize = mix(gridSize1, gridSize2, j / 2.0);
            pos1.xz += offsets[i] * gridSize;

            float h = mix(h1, h2, map11_01(0.5 * (sin(7.1 * pos1.x + 1.8 * j) + sin(9.3 * pos1.z + 1.5 * j))));
            h += j * h3;
            h *= rocksMask2;

            vec3 dir = vec3y1;
            dir += getWindForce(vec3(pos.xz + offsets[i] * 0.3, pos.y).xzy, time) * rocksMask1;
            dir.y = max(0.0, dir.y);
            dir = normalize(dir);
            dir *= h;

            float y = clamp(pos1.y / dir.y, 0.0, 1.0);

            pos1.xz -= 0.2 * dir.xz * pow(y, 2.0); // curve

            vec2 gridOffset = y * dir.xz; // offset grid index based on the direction relative to the queried position height
            vec2 index = floor((pos1.xz - gridOffset) / gridSize + 0.5);
            vec3 pos2 = pos1;

            float h1 = hash(index);
            float h2 = hash(index + 1000.0);

            pos2.xz -= index * gridSize;
            pos2.xz += 0.3 * gridSize * map01_11(vec2(h1, h2)); // jitter

            float r = mix(r2, r1, y);
            float d2 = sdCapsule(pos2, vec3(0.0), dir, r);

            rootPos = d2 < d1 ? index * gridSize : rootPos;
            d1 = min(d1, d2);
        }
    }

    vec3 d = vec3(d1, MATERIAL_GRASS, 0.0);
    d.yz += fract(rootPos / 1000.0 + 0.5); // serialize root position
    return d;
}

vec3 sdGround(vec3 pos)
{
    vec3 d = vec3(pos.y, MATERIAL_GRASS, 0.0);
    d.yz += fract(pos.xz / 1000.0 + 0.5);
    return d;
}

vec3 sdMountains(vec3 pos)
{
    const float scale = 200.0;

    const float f = 2.0;
    const float r1 = 2.0;
    const float h1 = 1.6;
    const float thickness1 = 0.8;
    const float count1  = 4.0;
    const float offset1 = -1.4;

    const float r2 = 3.0;
    const float h2 = 2.0;
    const float thickness2 = 1.0;
    const float variation2 = 0.3;
    const float count2  = 3.0;
    const float offset2 = 3.6;

    const float bumps = 0.2;
    const float details = 2.5;
    const float seed = 0.0;

    pos /= scale;

    vec3 pos1 = pos;

    float r = length(pos1.xz);

    float bounds = (abs(r - 3.0) - 2.0) * scale;
    if (bounds > BOUNDS_MARGIN)
    {
        return vec3(bounds, 0.0, 0.0);
    }

    pos1.y -= bumps * fbm(pos1 * details + seed) - 0.1;
    pos1.y += thickness1;

    float an = atan(pos1.z, pos1.x);

    float d1 = sdCircle(pos1.xz, r1);
    float h = pow(map11_01(sin(count1 * an + offset1)), 0.8) * h1;
    d1 = length(vec2(d1, stretchAxis(pos1.y, h)));
    d1 -= thickness1;

    float mask = smoothstep(0.0, 1.0, abs(an + PI05)); // front valley mask

    float d2 = sdCircle(pos1.xz, r2);
    h = pow(map11_01(sin(count2 * an + PI + offset2)) + 0.05, 0.3) * h2;
    h *= 1.0 + variation2 * sin((count2 - 1.0) * an); // variation
    h *= mask;
    d2 = length(vec2(d2, stretchAxis(pos1.y, h)));
    d2 -= thickness2 * mask;

    d1 = min(d1, d2);

    d1 = smin(d1, pos.y + 0.1, 0.8);
    d1 = max(d1, -pos.y);
    d1 = max(d1, r - r2 - 2.0 * thickness2);

    return vec3(d1 * scale, MATERIAL_MOUNTAIN, 0.0);
}

vec3 sdBackground(vec3 pos)
{
    vec3 d1 = vec3(MAX_DIST, MATERIAL_SKY, 0.0);
    vec3 d2, pos1;

    pos1 = pos;
    pos1.xz -= state.origin.xz;
    d2 = sdMountains(pos1);
    d1 = minx(d1, d2);

    pos1 = pos;
    pos1.y -= getGroundHeight(pos1);

    d2 = sdGround(pos1);
    d1 = minx(d1, d2);

    return d1;
}

float mapCollision(vec3 pos, float time)
{
    return MAX_DIST;
}

vec3 map(vec3 pos, float time)
{
    vec3 pos1 = pos;
    pos1.y -= getGroundHeight(vec3(pose.offset.xz, 0.0).xzy);
    vec3 d1 = sdMoomin(pos1);

    pos1 = pos;
    pos1.y -= getGroundHeight(pos1);

    if (state.theme < 1.0)
    {
        return d1;
    }

    vec3 d2;

    d2 = sdGround(pos1);
    d1 = minx(d1, d2);

    d2 = sdRocks(pos1);
    d1 = minx(d1, d2);

    d2 = sdGrass(pos1, time);
    d1 = minx(d1, d2);

    d2 = sdFlowers(pos1, time);
    d1 = minx(d1, d2);

    return d1;
}

vec3 mapReflection(vec3 pos, float time)
{
    return vec3(MAX_DIST, 0.0, 0.0);
}

vec2 mapTransparent(vec3 pos, float time)
{
    return vec2(MAX_DIST, 0.0);
}

vec3 getNormalTransparent(vec3 pos, float time)
{
    vec3 n = vec3(0.0);

    for (int i = 0; i < 4; i++)
    {
        vec3 d = 2.0 * vec3(((i + 3) >> 1) & 1, (i >> 1) & 1, i & 1) - 1.0;
        vec2 dm = mapTransparent(pos + 0.05 * d, time);

        n += dm.y > 0.0 ? d * dm.x : vec3(0.0);
    }

    return normalize(n);
}

vec3 castRay(vec3 ro, vec3 rd, float time, int maxSteps) // ray origin, ray direction
{
    float d = 0.0; // distance from ray origin
    vec2 m = vec2(0.0); // material

    for (int i = 0; i < maxSteps; i++)
    {
        vec3 pos = ro + rd * d; // current position

        vec3 d1 = map(pos, time); // distance from current position to the scene
        d += d1.x;
        m = d1.yz;

        marchSteps++;

        if (d > MAX_DIST || abs(d1.x / (d + 1.0)) < SURF_DIST)
        {
            break;
        }
    }

    if (d > MAX_DIST || m.x < MATERIAL_EMPTY + 1.0)
    {
        m = vec2(MATERIAL_SKY, 0.0);
        d = MAX_DIST;
    }

    return vec3(d, m);
}

vec3 castRayBackground(vec3 ro, vec3 rd, float time, int maxSteps, float maxDistance) // ray origin, ray direction
{
    float d = 0.0; // distance from ray origin
    vec2 m = vec2(0.0); // material

    int i;
    for (i = 0; i < maxSteps; i++)
    {
        vec3 pos = ro + rd * d; // current position

        vec3 dm = sdBackground(pos); // distance from current position to the scene
        d += dm.x;
        m = dm.yz;
        marchSteps++;

        if (d > maxDistance || abs(dm.x / (d + 1.0)) < SURF_DIST)
        {
            break;
        }
    }

    if (d > maxDistance || m.x < 1.0)
    {
        m = vec2(MATERIAL_SKY, 0.0);
        d = MAX_DIST;
    }

    return vec3(d, m);
}


vec3 castRayReflection(vec3 ro, vec3 rd, float time, int maxSteps) // ray origin, ray direction
{
    float d = 0.0; // distance from ray origin
    vec2 m = vec2(0.0); // material

    for (int i = 0; i < maxSteps; i++)
    {
        vec3 pos = ro + rd * d; // current position

        vec3 d1 = mapReflection(pos, time); // distance from current position to the scene
        d += d1.x;
        m = d1.yz;

        marchReflectionSteps++;

        if (d > MAX_DIST || abs(d1.x / (d + 1.0)) < SURF_DIST)
        {
            break;
        }
    }

    if (d > MAX_DIST || m.x < MATERIAL_EMPTY + 1.0)
    {
        m = vec2(MATERIAL_SKY, 0.0);
        d = MAX_DIST;
    }

    return vec3(d, m);
}

vec2 castRayTransparent(vec3 ro, vec3 rd, float time, int maxSteps, float maxDistance)
{
    float d = 0.0;
    float m = 0.0;

    for (int i = 0; i < maxSteps; i++)
    {
        vec3 pos = ro + rd * d;

        vec2 d1 = mapTransparent(pos, time);
        d += d1.x;
        m = d1.y;

        marchTransparentSteps++;

        if (d > maxDistance)
        {
            return vec2(MAX_DIST, 0.0);
        }

        if (abs(d1.x / (d + 1.0)) < SURF_DIST)
        {
            break;
        }
    }

    return vec2(d, m);
}

float castRayCollision(vec3 ro, vec3 rd, float time, int maxSteps) // ray origin, ray direction
{
    float d = 0.0; // distance from ray origin

    for (int i = 0; i < maxSteps; i++)
    {
        vec3 pos = ro + rd * d; // current position

        float d1 = mapCollision(pos, time); // distance from current position to the scene
        d += d1;

        if (d > MAX_DIST || abs(d1 / (d + 1.0)) < SURF_DIST)
        {
            break;
        }
    }

    return min(d, MAX_DIST);
}

float castShadow(vec3 ro, vec3 rd, float time)
{
    float result = 1.0;
    float d = 0.01; // position

    for (int i = 0; i < 50; i++)
    {
        vec3 pos = ro + d * rd;
        vec3 d1 = map(pos, time);

        marchShadowSteps++;

        if (!materialCastsShadow(floor(d1.y)))
        {
            d1.x += 0.01; // skip object
        }
        else
        {
            result = min(result, max(0.0, 40.0 * d1.x / d)); // soft shadow
        }

        d += max(d1.x, 0.01);

        if (abs(d1.x) < (d * 0.001) || d > MAX_DIST)
        {
            break;
        }
    }

    return clamp(1.0 - result, 0.0, 1.0);
}

float castShadowTransparent(vec3 ro, vec3 rd, float time)
{
    float result = 1.0;
    float d = 0.01; // position

    for (int i = 0; i < 50; i++)
    {
        vec3 pos = ro + d * rd;
        vec2 d1 = mapTransparent(pos, time);

        marchShadowSteps++;

        if (!materialCastsShadow(floor(d1.y)))
        {
            d1.x += 0.01; // skip object
        }
        else
        {
            result = min(result, max(0.0, 40.0 * d1.x / d)); // soft shadow
        }

        d += max(d1.x, 0.01);

        if (abs(d1.x) < (d * 0.001) || d > MAX_DIST)
        {
            break;
        }
    }

    return clamp(1.0 - result, 0.0, 1.0);
}

void getViewAxis(in vec3 origin, in vec3 target, out vec3 viewOrigin, out vec3 viewX, out vec3 viewY, out vec3 viewZ)
{
    origin.y = max(origin.y, getGroundHeight(origin) + MIN_CAMERA_HEIGHT);

    viewOrigin = origin;
    viewZ = normalize(target - origin);
    viewX = normalize(cross(viewZ, vec3(0.0, 1.0, 0.0)));
    viewY = cross(viewX, viewZ);
}

bool isKeyDown(int key)
{
    return keyboardTexture((vec2(0.5) + vec2(float(key), 0.0))).x > 0.5;
}

bool isKeyPressed(int key)
{
    return keyboardTexture((vec2(0.5) + vec2(float(key), 1.0))).x > 0.5;
}

vec2 scaleMouseCoordinate(vec2 coord)
{
    vec2 uv = map01_11(coord / iResolution.xy);
    uv *= state.renderScale;
    return map11_01(uv) * iResolution.xy;
}

vec3 getPosition(vec2 fragCoord)
{
    vec4 t = inputTexture(fragCoord);

    vec2 uv = map01_11(fragCoord / iResolution.xy);
    uv.x *= iResolution.x / iResolution.y;

    float depth = deserializeDepth(getDepthComponent(t));
    vec3 rd = normalize(uv.x * state.viewX + uv.y * state.viewY + FIELD_OF_VIEW * state.viewZ * state.renderScale);

    vec3 pos = state.viewOrigin + depth * rd; // point in scene

    return pos;
}

void updateState(vec2 fragCoord, float delta, float time)
{
    bool toggleRenderModeAction = isKeyPressed(KEY_F1);
    bool toggleThemeAction = isKeyPressed(KEY_F2);
    bool toggleNavigationModeAction = isKeyPressed(KEY_N);
    bool resetViewAction = isKeyPressed(BUTTON_RIGHT) || isKeyPressed(KEY_R);
    bool scaleUpRenderAction = isKeyPressed(KEY_KP_PLUS) || isKeyPressed(KEY_EQUALS);
    bool scaleDownRenderAction = isKeyPressed(KEY_KP_MINUS) || isKeyPressed(KEY_MINUS);
    bool zoomInAction = isKeyPressed(MOUSE_SCROLL_UP);
    bool zoomOutAction = isKeyPressed(MOUSE_SCROLL_DOWN);
    bool moveLeftAction = isKeyDown(KEY_A);
    bool moveRightAction = isKeyDown(KEY_D);
    bool moveForwardAction = isKeyDown(KEY_W);
    bool moveBackwardAction = isKeyDown(KEY_S);
    bool moveUpAction = isKeyDown(KEY_E);
    bool moveDownAction = isKeyDown(KEY_C);
    bool startDragAction = isKeyPressed(BUTTON_LEFT) || isKeyPressed(BUTTON_MIDDLE) || iMouse.w > 0.0;
    bool dragAction = isKeyDown(BUTTON_LEFT) || isKeyDown(BUTTON_MIDDLE) || iMouse.z > 0.0;
    bool dragZoomModifier = isKeyDown(KEY_CONTROL);
    bool dragPanModifier = isKeyDown(KEY_SHIFT);
    bool moveModifier = isKeyDown(KEY_SHIFT);

    bool isMouseOverViewport = iMouse.x > 0.0 && iMouse.y > 0.0 && iMouse.x < iResolution.x && iMouse.y < iResolution.y;
    bool moveAction = moveLeftAction || moveRightAction || moveForwardAction || moveBackwardAction;

    if (iMouse.z > 0.0 || isKeyPressed(BUTTON_LEFT) || isKeyPressed(BUTTON_MIDDLE) || isKeyPressed(BUTTON_RIGHT))
    {
        state.focused = isMouseOverViewport;
    }

    state.focused = true; // override

    float zoomOffset = 0.0;
    vec3 panOffset = vec3(0.0);
    vec2 swivelOffset = vec2(0.0);

    bool isDragging = length(state.dragStartPosition) > 0.0;
    bool isClicked = isDragging && !dragAction && state.navigationMode < 2.0 && (time - state.dragStartTime < CLICK_TIME && length(iMouse.xy - state.dragStartPosition) < 20.0);

    if (isClicked)
    {
        state.clickCount = time - state.clickTime > 0.0 && time - state.clickTime < CLICK_TIME ? state.clickCount + 1.0 : 0.0;
        state.clickTime = time;
    }

    if (state.focused)
    {
        if (toggleRenderModeAction)
        {
            state.nextRenderMode = mod(state.renderMode + 1.0, 8.0);
            state.modeAnnotation = vec2(1.0, time);
        }

        if (toggleThemeAction)
        {
            state.nextTheme = mod(state.nextTheme + 1.0, 3.0);
            state.modeAnnotation = vec2(2.0, time);
        }

        if (toggleNavigationModeAction)
        {
            state.navigationMode = mod(min(state.navigationMode, 1.0) + 1.0, 2.0);
            state.modeAnnotation = vec2(3.0, time);
        }

        if (scaleUpRenderAction)
        {
            state.nextRenderScale = clamp(state.renderScale * 1.1, 0.01, 1.0);
            state.modeAnnotation = vec2(4.0, time);
        }

        if (scaleDownRenderAction)
        {
            state.nextRenderScale = clamp(state.renderScale / 1.1, 0.01, 1.0);
            state.modeAnnotation = vec2(4.0, time);
        }

        if (resetViewAction)
        {
            resetState();
            state.focused = true;
        }

        float moveSpeed = moveModifier ? MOVE_SPEED2 : MOVE_SPEED1;

        if (moveLeftAction)
        {
            panOffset.x = delta * moveSpeed;
        }

        if (moveRightAction)
        {
            panOffset.x = -delta * moveSpeed;
        }

        if (moveForwardAction)
        {
            panOffset.z = -delta * moveSpeed;
        }

        if (moveBackwardAction)
        {
            panOffset.z = delta * moveSpeed;
        }

        if (moveUpAction)
        {
            panOffset.y = -delta * moveSpeed * 0.5;
        }

        if (moveDownAction)
        {
            panOffset.y = delta * moveSpeed * 0.5;
        }
    }

    if (isMouseOverViewport)
    {
        if (zoomInAction)
        {
            zoomOffset = -ZOOM_SCROLL_SPEED;
        }

        if (zoomOutAction)
        {
            zoomOffset = ZOOM_SCROLL_SPEED;
        }

        if (startDragAction)
        {
            state.dragStartTime = time;
            state.dragStartPosition = iMouse.xy;
            state.dragLastPosition = iMouse.xy;
            isDragging = true;
        }
    }

    if (dragAction || moveAction)
    {
        state.targetAnnotation = vec4(0.0);
        state.modeAnnotation = vec2(0.0);
    }

    if (!dragAction)
    {
        state.dragStartPosition = vec2(0.0);
        state.dragLastPosition = vec2(0.0);
        isDragging = false;
    }

    if (isDragging && dragAction)
    {
        vec2 dragOffset = (iMouse.xy - state.dragLastPosition) / iResolution.y;
        state.dragLastPosition = iMouse.xy;

        if (dragZoomModifier && !moveAction)
        {
            zoomOffset = -ZOOM_DRAG_SPEED * sign(dragOffset.y) * 2.0 * length(dragOffset);
        }
        else if (dragPanModifier && !moveAction)
        {
            panOffset = vec3(dragOffset.xy, 0.0);
        }
        else // swivel
        {
            swivelOffset = SWIVEL_SPEED * dragOffset.xy;
        }
    }

    vec3 viewDirection = state.target - state.origin;
    float viewDistance = length(viewDirection);

    vec2 viewRotation = vec2(atan(viewDirection.z, viewDirection.x), atan(viewDirection.y, length(viewDirection.xz)));

    if (state.navigationMode > 1.0)
    {
        panOffset = vec3(0.0);
    }

    if (state.navigationMode < 1.0) // walk mode (0)
    {
        vec3 origin = state.origin;

        vec3 d1 = vec3(castRayCollision(origin, vec3y(-1.0), time, MAX_STEPS), 100.0, 0.0);

        float targetHeight = MOVE_CAMERA_HEIGHT + max(getGroundHeight(state.origin), origin.y - d1.x);

        vec3 moveZ = normalize(vec3(state.viewZ.xz, 0.0).xzy);
        vec3 moveY = vec3y(1.0);
        vec3 moveX = cross(moveZ, moveY);
        vec3 targetOffset = panOffset.x * moveX + panOffset.z * moveZ;

        viewRotation += swivelOffset.xy * 0.5;
        viewRotation.y = clamp(viewRotation.y, -PI05 + 0.001, PI05 - 0.001);

        vec3 target = origin + viewDistance * vec3(cos(viewRotation.x) * cos(viewRotation.y), sin(viewRotation.y), sin(viewRotation.x) * cos(viewRotation.y));

        origin -= targetOffset;
        target -= targetOffset;

        targetHeight = clamp(targetHeight, origin.y - MOVE_GRAVITY * delta, origin.y + MOVE_COLLISION * delta);
        target.y += targetHeight - origin.y;
        origin.y = targetHeight;

        // teleport
        if (isClicked && state.clickCount > 0.0) // double click
        {
            vec3 clickPosition = getPosition(scaleMouseCoordinate(iMouse.xy));
            float d1 = length(clickPosition - state.origin);

            if (d1 < 300.0) // exclude mountains and sky
            {
                vec3 pos = clickPosition; // point in scene
                pos.y += MOVE_CAMERA_HEIGHT;
                target += pos - origin;
                origin = pos;
            }
        }

        state.nextOrigin = origin;
        state.nextTarget = target;
    }
    else // inspection mode (1)
    {
        // zoom
        viewDistance *= pow(2.0, zoomOffset);

        // swivel
        viewRotation.xy += swivelOffset;
        viewRotation.y = clamp(viewRotation.y, -PI05 + 0.001, PI05 - 0.001);

        // pan
        vec3 panX = state.viewX;
        vec3 panZ = normalize(vec3(state.viewZ.xz, 0.0).xzy);
        vec3 panY = cross(panX, panZ);
        vec3 targetOffset = viewDistance * (panOffset.x * panX + panOffset.y * panY + panOffset.z * panZ);

        state.nextOrigin = state.target - targetOffset - viewDistance * vec3(cos(viewRotation.x) * cos(viewRotation.y), sin(viewRotation.y), sin(viewRotation.x) * cos(viewRotation.y));
        state.nextTarget = state.target - targetOffset;

        // re-center target
        state.nextTargetOffset *= max(0.0, 1.0 - 0.5 * length(swivelOffset) - length(panOffset) - abs(zoomOffset) - length(panOffset));

        if (isClicked)
        {
            vec3 clickPosition = getPosition(scaleMouseCoordinate(iMouse.xy));
            float d1 = length(clickPosition - state.origin);

            #ifdef RENDER_TRANSPARENCY
                float d2 = castRayTransparent(state.origin, state.viewZ, time, MAX_STEPS, MAX_DIST).x;
                d1 = min(d1, d2);
            #endif

            if (d1 < 100.0) // limit distance
            {
                vec3 target = clickPosition; // point in scene

                state.nextTargetOffset += state.target - target;
                state.nextTarget = target;
                state.targetAnnotation = vec4(iMouse.xy, time, 1.0);

                if (state.clickCount > 0.0) // double click
                {
                    state.nextTargetOffset = vec3(0.0);
                    state.nextOrigin = target - 2.0 * normalize(viewDirection);
                }
            }
        }
    }

    if (length(state.nextOrigin - state.origin) < 0.0001)
    {
        state.nextOrigin = state.origin;
    }

    if (length(state.nextTarget - state.target) < 0.0001)
    {
        state.nextTarget = state.target;
    }
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    deserializeState(iChannel0, iResolution.xy);

    if (!state.initialized)
    {
        resetState();
        state.initialized = true;
        state.nextRenderMode = 0.0;
        state.nextRenderScale = 1.0;
        state.nextOrigin = INITIAL_ORIGIN;
        state.nextTarget = INITIAL_TARGET;
        state.nextTargetOffset = vec3(0.0);
        state.nextTheme = 1.0;
        state.navigationMode = 1.0;
    }

    state.origin = state.nextOrigin;
    state.target = state.nextTarget;
    state.targetOffset = state.nextTargetOffset;
    state.renderMode = state.nextRenderMode;
    state.renderScale = state.nextRenderScale;
    state.theme = state.nextTheme;

    vec3 origin = state.origin;
    vec3 target = state.target + state.targetOffset;

    float time = iTime;

    setPose(happyKeyframe);

    // Empty pose:
    //setPose(emptyKeyframe);

    // Simple animation:
    //Keyframe targetKeyframe = happyKeyframe;
    //if (fract(time / 2.0) < 0.5)
    //{
    //    targetKeyframe = mirrorKeyframe(targetKeyframe);
    //}
    //setPose(mixKeyframe(emptyKeyframe, targetKeyframe, pow(abs(sin(time * PI)), 0.8)));

    vec2 uv = map01_11(fragCoord / iResolution.xy);

    if (fragCoord.x < STATE_SIZE && fragCoord.y < 1.0) // state
    {
        float delta = iTimeDelta;

        vec3 origin, rdx, rdy, rdz;
        getViewAxis(state.origin, state.target + state.targetOffset, origin, rdx, rdy, rdz);

        state.viewX = rdx;
        state.viewY = rdy;
        state.viewZ = rdz;
        state.viewOrigin = origin;

        updateState(fragCoord, delta, time);

        fragColor = serializeState(int(floor(fragCoord.x)));
    }
    else if (abs(uv.x) < state.renderScale && abs(uv.y) < state.renderScale)
    {
        // ray direction
        vec3 origin, rdx, rdy, rdz;
        getViewAxis(state.origin, state.target + state.targetOffset, origin, rdx, rdy, rdz);

        uv.x *= iResolution.x / iResolution.y;
        int steps = 0;
        vec3 rd = normalize(uv.x * rdx + uv.y * rdy + FIELD_OF_VIEW * rdz * state.renderScale);
        vec3 d1 = castRay(origin, rd, time, MAX_STEPS);

        if (state.theme < 1.0)
        {
            fragColor = vec4(serializeDepth(d1.x), d1.y, d1.z, 0.0);
            return;
        }

        vec3 d2 = castRayBackground(origin, rd, time, MAX_STEPS, d1.x);
        d1 = minx(d1, d2);

        vec3 pos = origin + d1.x * rd; // point in scene

        float tint = 0.0;

        #ifdef RENDER_TRANSPARENCY
            vec2 d2 = castRayTransparent(origin, rd, time, MAX_STEPS, d1.x);
            vec3 pos2 = origin + d2.x * rd; // transparent point in scene
            vec3 n2 = getNormalTransparent(pos2, time); // transparent normal

            // transparent tint
            tint = d2.y;
            // reflection
            if (tint >= MATERIAL_REFLECTION_START)
            {
                vec3 r = reflect(rd, n2);
                vec3 d3 = castRayReflection(pos2, r, time, MAX_STEPS);

                // reflection tint
                tint += d3.x > 10.0 ? 0.0 : 1.0;

                // reflection outline group
                d1.z += d3.x < 10.0 ? (2.0 + floor(d3.y) + floor(d3.z)) : 1.0;
            }
            else if (tint >= MATERIAL_TRANSPARENT_START)
            {
                vec3 r = reflect(rd, n2);
                tint += dot(r, SUN_DIRECTION) > 0.8 ? 1.0 : 0.0;
            }

            d1.x = min(d1.x, d2.x);
        #endif

        float shadow = castShadow(pos, SUN_DIRECTION, time);

        #ifdef RENDER_TRANSPARENCY_SHADOW
            shadow += castRayTransparent(pos, SUN_DIRECTION, time, MAX_STEPS, MAX_DIST).y > 0.0 ? 0.5 : 0.0;
        #endif

        shadow = d1.y > MATERIAL_SKY ? shadow : 0.0;
        shadow = clamp(shadow, 0.0, 0.99);

        if (state.renderMode == 1.0) // override uv with ray march steps count
        {
            int steps = marchSteps;
            steps += marchTransparentSteps;
            steps += marchReflectionSteps;
            steps += marchShadowSteps;

            d1.z = floor(d1.z) + min(0.99, 0.5 * (float(steps) / float(MAX_STEPS)));
        }
        else if (d1.y >= MATERIAL_GRASS && d1.y < MATERIAL_GRASS + 1.0)
        {
            vec2 rootPos = fract(d1.yz) * 1000.0; // deserialize root position
            float h = (pos.y - getGroundHeight(pos)) / 0.2;
            d1.y = MATERIAL_GRASS + 0.99 * getGrassShade(rootPos);
            d1.z = 0.9 * clamp(h, 0.0, 1.0);
        }

        fragColor = vec4(serializeDepth(d1.x), d1.y, d1.z, tint + shadow);
    }
}
