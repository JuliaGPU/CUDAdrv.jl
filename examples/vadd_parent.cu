extern "C" {

__device__ float device_add(float a, float b);

__global__ void kernel_vadd(const float *a, const float *b, float *c)
{
    int i = blockIdx.x *blockDim.x + threadIdx.x;
    c[i] = device_add(a[i], b[i]);
}

}
