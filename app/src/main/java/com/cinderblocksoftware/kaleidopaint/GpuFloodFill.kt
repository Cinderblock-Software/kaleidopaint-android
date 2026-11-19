// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.opengl.GLES31.*
import com.cinderblocksoftware.kaleidopaint.geometry.FillMask
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Exact-color toroidal eight-way fill, using horizontal run labels and a monotone atomic union
 * forest. Implements the original fill semantics rather than its Metal queue layout. The input
 * texture is read-only throughout: failure can fall back to the CPU without restoring a partially
 * changed image. Only the compressed horizontal runs are mapped back to the host. All methods must
 * run on the owning GL context/thread.
 */
internal class GpuFloodFill(private val size: Int) : AutoCloseable {
    private val buffers = IntArray(4)
    private val programs = ArrayList<Int>()
    private val maxRuns = maxOf(1, size * size / 2)

    init {
        require(size in 1..4096 && size and (size - 1) == 0)
        check(supported()) { "Compute shaders unavailable" }
        try {
            val maxBlock = LongArray(1)
            glGetInteger64v(GL_MAX_SHADER_STORAGE_BLOCK_SIZE, maxBlock, 0)
            check(maxBlock[0] >= maxOf(8, size * size * 4)) { "Compute storage limit" }
            glGenBuffers(4, buffers, 0)
            for (i in buffers.indices) {
                glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffers[i])
                glBufferData(
                    GL_SHADER_STORAGE_BUFFER,
                    if (i == 3) 16 else maxOf(8, size * size * 4),
                    null,
                    GL_DYNAMIC_COPY,
                )
                check(glGetError() == GL_NO_ERROR) { "Compute storage allocation failed" }
            }
            programs.add(compile(common + initializeRows))
            programs.add(compile(common + forest + joinRows))
            programs.add(compile(common + forest + emitRuns))
        } catch (error: Throwable) {
            close()
            throw error
        }
    }

    /** Bounded topology work exhausted its budget; the backend remains usable. */
    class WorkLimitException(val failureBits: Int, val runCount: Int) :
        RuntimeException("Compute work limit: $failureBits/$runCount")

    fun compute(texture: Int, seeds: IntArray, color: Int): FillMask {
        require(seeds.size in 1..12 && seeds.all { it in 0 until size * size })
        for (i in buffers.indices) glBindBufferBase(GL_SHADER_STORAGE_BUFFER, i, buffers[i])
        val zero = ByteBuffer.allocateDirect(16).order(ByteOrder.nativeOrder())
        glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffers[3])
        glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, 16, zero)
        glMemoryBarrier(
            GL_FRAMEBUFFER_BARRIER_BIT or
                GL_SHADER_IMAGE_ACCESS_BARRIER_BIT or
                GL_BUFFER_UPDATE_BARRIER_BIT
        )
        glBindImageTexture(0, texture, 0, false, 0, GL_READ_ONLY, GL_RGBA8)
        try {
            for (program in programs) {
                glUseProgram(program)
                glUniform1ui(glGetUniformLocation(program, "n"), size)
                glUniform1ui(glGetUniformLocation(program, "fillColor"), color)
                glUniform1ui(glGetUniformLocation(program, "seedCount"), seeds.size)
                glUniform1uiv(glGetUniformLocation(program, "seeds[0]"), seeds.size, seeds, 0)
                glDispatchCompute((size + 63) / 64, 1, 1)
                glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT)
            }
            glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT)
            check(glGetError() == GL_NO_ERROR) { "Compute dispatch failed" }
            glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffers[3])
            val status =
                glMapBufferRange(GL_SHADER_STORAGE_BUFFER, 0, 16, GL_MAP_READ_BIT) as? ByteBuffer
                    ?: error("Compute status readback failed")
            val count: Int
            val failure: Int
            try {
                status.order(ByteOrder.nativeOrder())
                count = status.getInt(0)
                failure = status.getInt(4)
            } finally {
                check(glUnmapBuffer(GL_SHADER_STORAGE_BUFFER))
            }
            check(glGetError() == GL_NO_ERROR) { "Compute status readback failed" }
            check(failure and 7.inv() == 0) { "Unknown compute status: $failure" }
            if (failure != 0) throw WorkLimitException(failure, count)
            check(count in 0..maxRuns) { "Invalid compute run count: $count" }
            if (count == 0) return FillMask(size, IntArray(0))
            glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffers[2])
            val mapped =
                glMapBufferRange(GL_SHADER_STORAGE_BUFFER, 0, count * 8, GL_MAP_READ_BIT)
                    as? ByteBuffer ?: error("Compute run readback failed")
            val runs = IntArray(count * 2)
            try {
                mapped.order(ByteOrder.nativeOrder()).asIntBuffer().get(runs)
            } finally {
                check(glUnmapBuffer(GL_SHADER_STORAGE_BUFFER))
            }
            check(glGetError() == GL_NO_ERROR) { "Compute readback failed" }
            return FillMask(size, runs)
        } finally {
            glBindImageTexture(0, 0, 0, false, 0, GL_READ_ONLY, GL_RGBA8)
            for (i in buffers.indices) glBindBufferBase(GL_SHADER_STORAGE_BUFFER, i, 0)
            glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0)
        }
    }

    override fun close() {
        if (buffers.any { it != 0 }) glDeleteBuffers(4, buffers, 0)
        buffers.fill(0)
        programs.forEach { glDeleteProgram(it) }
        programs.clear()
    }

    companion object {
        fun supported(): Boolean {
            val version = IntArray(2)
            glGetIntegerv(GL_MAJOR_VERSION, version, 0)
            glGetIntegerv(GL_MINOR_VERSION, version, 1)
            return version[0] > 3 || version[0] == 3 && version[1] >= 1
        }

        private fun compile(source: String): Int {
            val shader = glCreateShader(GL_COMPUTE_SHADER)
            var program = 0
            try {
                glShaderSource(shader, source)
                glCompileShader(shader)
                val status = IntArray(1)
                glGetShaderiv(shader, GL_COMPILE_STATUS, status, 0)
                check(status[0] != 0) { glGetShaderInfoLog(shader) }
                program = glCreateProgram()
                glAttachShader(program, shader)
                glLinkProgram(program)
                glGetProgramiv(program, GL_LINK_STATUS, status, 0)
                check(status[0] != 0) { glGetProgramInfoLog(program) }
                return program
            } catch (error: Throwable) {
                if (program != 0) glDeleteProgram(program)
                throw error
            } finally {
                glDeleteShader(shader)
            }
        }

        private val common =
            """
            #version 310 es
                        precision highp float;
                        precision highp int;
                        layout(local_size_x=64) in;
                        layout(rgba8,binding=0) readonly uniform highp image2D sourceImage;
                        layout(std430,binding=0) buffer Labels { uint labels[]; };
                        layout(std430,binding=1) coherent buffer Parents { uint parents[]; };
                        layout(std430,binding=2) buffer Runs { uvec2 runs[]; };
                        layout(std430,binding=3) coherent buffer State { uint runCount; uint failure; uint unused0; uint unused1; };
                        uniform uint n;
                        uniform uint fillColor;
                        uniform uint seedCount;
                        uniform uint seeds[12];
                        const uint NONE=0xffffffffu;
            """
                .trimIndent() + "\n"
        private val initializeRows =
            """
            void main() {
                uint y=gl_GlobalInvocationID.x;if(y>=n)return;
                uint target=packUnorm4x8(imageLoad(sourceImage,ivec2(seeds[0]%n,seeds[0]/n)));
                bool seedRow=false;
                for(uint s=0u;s<seedCount;s++)if(seeds[s]/n==y)seedRow=true;
                uint label=NONE;
                for(uint x=0u;x<n;x++) {
                    uint index=y*n+x;
                    bool eligible=target!=fillColor && packUnorm4x8(imageLoad(sourceImage,ivec2(x,y)))==target;
                    // Normalize all symmetrical seeds to the first seed's color,
                    // exactly as the CPU oracle does, except for a no-op fill.
                    if(target!=fillColor && !eligible && seedRow)
                        for(uint s=0u;s<seedCount;s++)if(seeds[s]==index)eligible=true;
                    if(eligible) {
                        if(label==NONE){label=index;parents[label]=label;}
                        labels[index]=label;
                    } else {labels[index]=NONE;label=NONE;}
                }
            }
        """
        private val forest =
            """
            uint root(uint node) {
                // Atomic loads and monotone path compression avoid mixed atomic/
                // non-atomic access to concurrently changing parent pointers.
                for(uint attempt=0u;attempt<256u;attempt++) {
                    uint p=atomicAdd(parents[node],0u);
                    if(p==node)return node;
                    uint grand=atomicAdd(parents[p],0u);
                    atomicMin(parents[node],grand);node=grand;
                }
                atomicOr(failure,1u);return node;
            }
            void unite(uint a,uint b) {
                if(a==NONE || b==NONE)return;
                for(uint attempt=0u;attempt<64u;attempt++) {
                    uint ra=root(a),rb=root(b);if(ra==rb)return;
                    uint hi=max(ra,rb),lo=min(ra,rb);
                    if(atomicCompSwap(parents[hi],hi,lo)==hi)return;
                }
                atomicOr(failure,2u);
            }
        """
        private val joinRows =
            """
            void main() {
                uint y=gl_GlobalInvocationID.x;if(y>=n)return;
                unite(labels[y*n],labels[y*n+n-1u]);
                uint next=((y+1u)&(n-1u))*n;
                uint previousA[3],previousB[3];
                for(int d=0;d<3;d++){previousA[d]=NONE;previousB[d]=NONE;}
                for(uint x=0u;x<n;x++) {
                    uint a=labels[y*n+x];
                    for(int d=0;d<3;d++) {
                        uint nx=(x+uint(d)+n-1u)&(n-1u);
                        uint b=labels[next+nx];
                        // An unchanged pair of horizontal runs needs one union,
                        // not a contended atomic union for every pixel in it.
                        if(a!=previousA[d] || b!=previousB[d])unite(a,b);
                        previousA[d]=a;previousB[d]=b;
                    }
                }
            }
        """
        private val emitRuns =
            """
            void main() {
                uint y=gl_GlobalInvocationID.x;if(y>=n)return;
                uint seedRoots[12];
                for(uint s=0u;s<seedCount;s++) {
                    uint label=labels[seeds[s]];seedRoots[s]=label==NONE?NONE:root(label);
                }
                uint x=0u;
                while(x<n) {
                    uint first=x,label=labels[y*n+x];x++;
                    if(label==NONE)continue;
                    while(x<n && labels[y*n+x]==label)x++;
                    uint r=root(label);bool selected=false;
                    for(uint s=0u;s<seedCount;s++)if(r==seedRoots[s])selected=true;
                    if(selected) {
                        uint slot=atomicAdd(runCount,1u);
                        if(slot>=max(1u,n*n/2u))atomicOr(failure,4u);
                        else runs[slot]=uvec2(y*n+first,x-first);
                    }
                }
            }
        """
    }
}
