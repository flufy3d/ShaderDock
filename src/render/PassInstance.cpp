#include "render/PassInstance.hpp"

#include <SDL.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <sstream>
#include <string>
#include <string_view>

#include <glad/glad.h>

#include "resources/AssetIO.hpp"

namespace shaderdock::render {

namespace {

constexpr const char* kFullscreenVertexShader = R"(#version 320 es
precision highp float;

const vec2 kPositions[3] = vec2[](
    vec2(-1.0, -1.0),
    vec2(3.0, -1.0),
    vec2(-1.0, 3.0)
);

out vec2 vUV;

void main()
{
    vec2 pos = kPositions[gl_VertexID];
    vUV = pos * 0.5 + 0.5;
    gl_Position = vec4(pos, 0.0, 1.0);
}
)";

std::string StripVersionPragmas(std::string_view source)
{
    std::ostringstream oss;
    std::istringstream iss{std::string(source)};
    std::string line;
    while (std::getline(iss, line)) {
        std::string trimmed = line;
        trimmed.erase(trimmed.begin(), std::find_if(trimmed.begin(), trimmed.end(), [](unsigned char ch) {
            return !std::isspace(ch);
        }));
        if (trimmed.rfind("#version", 0) == 0) {
            continue;
        }
        oss << line << '\n';
    }
    return oss.str();
}

std::string NormalizeMacroSuffix(std::string_view name)
{
    std::string result;
    result.reserve(name.size());
    bool last_underscore = false;
    for (char c : name) {
        unsigned char uc = static_cast<unsigned char>(c);
        if (std::isalnum(uc)) {
            result.push_back(static_cast<char>(std::toupper(uc)));
            last_underscore = false;
        } else {
            if (!last_underscore) {
                result.push_back('_');
                last_underscore = true;
            }
        }
    }
    while (!result.empty() && result.back() == '_') {
        result.pop_back();
    }
    return result;
}

std::array<resources::PassInputType, 4> BuildChannelTypes(const resources::RenderPass& pass)
{
    std::array<resources::PassInputType, 4> channel_types{};
    channel_types.fill(resources::PassInputType::kTexture);

    for (const auto& input : pass.inputs) {
        if (input.channel >= 0 && input.channel < 4) {
            channel_types[static_cast<std::size_t>(input.channel)] = input.type;
        }
    }

    return channel_types;
}

const char* SamplerTypeForChannel(resources::PassInputType input_type)
{
    if (input_type == resources::PassInputType::kCubemap) {
        return "samplerCube";
    }
    return "sampler2D";
}

} // namespace

bool PassInstance::initialize(
    const resources::RenderPass& pass,
    bool uses_history,
    BufferSurface* target_buffer,
    const std::unordered_map<std::string, BufferSurface*>& buffer_sources,
    const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings,
    const std::string& common_source)
{
    manifest_ = &pass;
    uses_history_ = uses_history;
    target_buffer_ = target_buffer;

    const std::string raw_source = load_pass_source(pass);
    if (raw_source.empty()) {
        return false;
    }

    const std::string fragment_source = build_fragment_source(pass, raw_source, common_source);
    if (!program_.compile_from_source(kFullscreenVertexShader, fragment_source.c_str())) {
        SDL_Log("PassInstance: failed to compile shader for %s.", pass.name.c_str());
        return false;
    }

    if (!build_input_bindings(pass, buffer_sources, texture_bindings)) {
        return false;
    }

    cache_uniform_locations();
    return true;
}

void PassInstance::bind_inputs() const
{
    for (const auto& binding : inputs_) {
        if (binding.channel < 0 || binding.channel > 3) {
            continue;
        }
        glActiveTexture(GL_TEXTURE0 + binding.channel);
        if (binding.type == resources::PassInputType::kTexture || binding.type == resources::PassInputType::kCubemap) {
            if (binding.texture) {
                glBindTexture(binding.texture->target(), binding.texture->id());
            }
        } else if (binding.type == resources::PassInputType::kBuffer) {
            if (binding.buffer != nullptr) {
                glBindTexture(GL_TEXTURE_2D, binding.buffer->read_texture());
            }
        }
    }
    glActiveTexture(GL_TEXTURE0);
}

void PassInstance::unbind_inputs() const
{
    for (const auto& binding : inputs_) {
        if (binding.channel < 0 || binding.channel > 3) {
            continue;
        }
        glActiveTexture(GL_TEXTURE0 + binding.channel);
        if (binding.type == resources::PassInputType::kTexture) {
            glBindTexture(GL_TEXTURE_2D, 0);
        } else if (binding.type == resources::PassInputType::kCubemap) {
            glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
        } else {
            glBindTexture(GL_TEXTURE_2D, 0);
        }
    }
    glActiveTexture(GL_TEXTURE0);
}

void PassInstance::apply_uniforms(const FrameUniforms& frame, int target_width, int target_height) const
{
    std::array<float, 4> channel_time = frame.channel_time;
    std::array<float, 12> channel_resolution{};

    for (const auto& binding : inputs_) {
        if (binding.channel < 0 || binding.channel > 3) {
            continue;
        }

        float width = 0.0F;
        float height = 0.0F;
        float time_value = channel_time[static_cast<std::size_t>(binding.channel)];

        if (binding.type == resources::PassInputType::kTexture || binding.type == resources::PassInputType::kCubemap) {
            if (binding.texture) {
                width = static_cast<float>(binding.texture->width());
                height = static_cast<float>(binding.texture->height());
            }
            time_value = frame.time_seconds;
        } else if (binding.type == resources::PassInputType::kBuffer) {
            if (binding.buffer != nullptr) {
                width = static_cast<float>(binding.buffer->width);
                height = static_cast<float>(binding.buffer->height);
                time_value = binding.buffer->last_updated_seconds;
            }
        }

        const int base = binding.channel * 3;
        channel_resolution[static_cast<std::size_t>(base)] = width;
        channel_resolution[static_cast<std::size_t>(base + 1)] = height;
        channel_resolution[static_cast<std::size_t>(base + 2)] = 1.0F;
        channel_time[static_cast<std::size_t>(binding.channel)] = time_value;
    }

    if (uniforms_.iResolution >= 0) {
        glUniform3f(
            uniforms_.iResolution,
            static_cast<float>(target_width),
            static_cast<float>(target_height),
            1.0F);
    }
    if (uniforms_.iTime >= 0) {
        glUniform1f(uniforms_.iTime, frame.time_seconds);
    }
    if (uniforms_.iTimeDelta >= 0) {
        glUniform1f(uniforms_.iTimeDelta, frame.delta_seconds);
    }
    if (uniforms_.iFrameRate >= 0) {
        glUniform1f(uniforms_.iFrameRate, frame.frame_rate);
    }
    if (uniforms_.iFrame >= 0) {
        glUniform1i(uniforms_.iFrame, frame.frame_index);
    }
    if (uniforms_.iMouse >= 0) {
        glUniform4fv(uniforms_.iMouse, 1, frame.mouse.data());
    }
    if (uniforms_.iDate >= 0) {
        glUniform4fv(uniforms_.iDate, 1, frame.date.data());
    }
    if (uniforms_.iChannelTime >= 0) {
        glUniform1fv(uniforms_.iChannelTime, 4, channel_time.data());
    }

    if (uniforms_.iChannelResolution >= 0) {
        glUniform3fv(uniforms_.iChannelResolution, 4, channel_resolution.data());
    }
}

std::string PassInstance::load_pass_source(const resources::RenderPass& pass) const
{
    std::string source = resources::ReadTextFile(pass.source_path.string());
    if (source.empty()) {
        SDL_Log("PassInstance: failed to read shader %s.", pass.source_file.c_str());
    }
    return source;
}

std::string PassInstance::build_fragment_source(const resources::RenderPass& pass, std::string_view raw, const std::string& common_source) const
{
    std::ostringstream oss;
    const auto channel_types = BuildChannelTypes(pass);

    oss << "#version 320 es\n";
    oss << "precision highp float;\n";
    oss << "layout(location = 0) out vec4 shaderdock_FragColor;\n";

    oss << "#define SHADERDOCK_PASS 1\n";
    if (pass.type == resources::RenderPassType::kImage) {
        oss << "#define SHADERDOCK_PASS_IMAGE 1\n";
    } else if (pass.type == resources::RenderPassType::kBuffer) {
        oss << "#define SHADERDOCK_PASS_BUFFER 1\n";
    }

    if (!pass.name.empty()) {
        const std::string macro_suffix = NormalizeMacroSuffix(pass.name);
        if (!macro_suffix.empty()) {
            oss << "#define SHADERDOCK_PASS_" << macro_suffix << " 1\n";
        }
    }

    if (!common_source.empty()) {
        oss << "#define SHADERDOCK_HAS_COMMON 1\n";
    }

    oss << R"(
uniform vec3 iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform float iFrameRate;
uniform int iFrame;
uniform vec4 iMouse;
uniform vec4 iDate;
uniform float iChannelTime[4];
uniform vec3 iChannelResolution[4];
)";

    for (int channel = 0; channel < 4; ++channel) {
        oss << "uniform " << SamplerTypeForChannel(channel_types[static_cast<std::size_t>(channel)]) << " iChannel"
            << channel << ";\n";
    }

    if (!common_source.empty()) {
        oss << "\n" << common_source << "\n";
    }

    oss << "\n" << StripVersionPragmas(raw) << "\n";

    oss << R"(
void main()
{
    vec4 fragColor = vec4(0.0);
    mainImage(fragColor, gl_FragCoord.xy);
    shaderdock_FragColor = fragColor;
}
)";

    return oss.str();
}

void PassInstance::cache_uniform_locations()
{
    program_.use();
    uniforms_.iResolution = program_.uniform_location("iResolution");
    uniforms_.iTime = program_.uniform_location("iTime");
    uniforms_.iTimeDelta = program_.uniform_location("iTimeDelta");
    uniforms_.iFrameRate = program_.uniform_location("iFrameRate");
    uniforms_.iFrame = program_.uniform_location("iFrame");
    uniforms_.iMouse = program_.uniform_location("iMouse");
    uniforms_.iDate = program_.uniform_location("iDate");
    uniforms_.iChannelTime = program_.uniform_location("iChannelTime");
    uniforms_.iChannelResolution = program_.uniform_location("iChannelResolution");

    for (int channel = 0; channel < 4; ++channel) {
        char name[16];
        std::snprintf(name, sizeof(name), "iChannel%d", channel);
        uniforms_.channel_samplers[channel] = program_.uniform_location(name);
        if (uniforms_.channel_samplers[channel] >= 0) {
            glUniform1i(uniforms_.channel_samplers[channel], channel);
        }
    }
}

bool PassInstance::build_input_bindings(
    const resources::RenderPass& pass,
    const std::unordered_map<std::string, BufferSurface*>& buffer_sources,
    const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings)
{
    inputs_.clear();
    inputs_.reserve(pass.inputs.size());

    for (const auto& input : pass.inputs) {
        if (input.channel < 0 || input.channel > 3) {
            SDL_Log(
                "PassInstance: input channel %d out of range for pass %s.",
                input.channel,
                pass.name.c_str());
            continue;
        }

        InputBinding binding;
        binding.channel = input.channel;
        binding.type = input.type;

        if (input.type == resources::PassInputType::kTexture || input.type == resources::PassInputType::kCubemap) {
            auto tex_it = texture_bindings.find(input.id);
            if (tex_it == texture_bindings.end() || !tex_it->second) {
                SDL_Log(
                    "PassInstance: missing texture binding '%s' for pass %s.",
                    input.id.c_str(),
                    pass.name.c_str());
                return false;
            }
            binding.texture = tex_it->second;
        } else if (input.type == resources::PassInputType::kBuffer) {
            auto surface_it = buffer_sources.find(input.id);
            if (surface_it == buffer_sources.end()) {
                SDL_Log(
                    "PassInstance: missing buffer source '%s' for pass %s.",
                    input.id.c_str(),
                    pass.name.c_str());
                return false;
            }
            binding.buffer = surface_it->second;
        }

        inputs_.emplace_back(std::move(binding));
    }

    return true;
}

} // namespace shaderdock::render
