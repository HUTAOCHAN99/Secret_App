// secret_app/lib/steganography/steganography.c
#include "steganography.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#define BLOCK_SIZE 8
#define MAX_CAPACITY_FACTOR 0.3  // 30% dari total pixels

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Fungsi DCT
void dct_transform(double block[BLOCK_SIZE][BLOCK_SIZE]) {
    double temp[BLOCK_SIZE][BLOCK_SIZE];
    double cu, cv, sum;
    
    for (int u = 0; u < BLOCK_SIZE; u++) {
        for (int v = 0; v < BLOCK_SIZE; v++) {
            sum = 0.0;
            cu = (u == 0) ? 1.0/sqrt(2.0) : 1.0;
            cv = (v == 0) ? 1.0/sqrt(2.0) : 1.0;
            
            for (int x = 0; x < BLOCK_SIZE; x++) {
                for (int y = 0; y < BLOCK_SIZE; y++) {
                    double cos1 = cos((2*x+1)*u*M_PI/16.0);
                    double cos2 = cos((2*y+1)*v*M_PI/16.0);
                    sum += block[x][y] * cos1 * cos2;
                }
            }
            temp[u][v] = 0.25 * cu * cv * sum;
        }
    }
    
    memcpy(block, temp, sizeof(temp));
}

// Fungsi inverse DCT
void idct_transform(double block[BLOCK_SIZE][BLOCK_SIZE]) {
    double temp[BLOCK_SIZE][BLOCK_SIZE];
    double cu, cv, sum;
    
    for (int x = 0; x < BLOCK_SIZE; x++) {
        for (int y = 0; y < BLOCK_SIZE; y++) {
            sum = 0.0;
            
            for (int u = 0; u < BLOCK_SIZE; u++) {
                for (int v = 0; v < BLOCK_SIZE; v++) {
                    cu = (u == 0) ? 1.0/sqrt(2.0) : 1.0;
                    cv = (v == 0) ? 1.0/sqrt(2.0) : 1.0;
                    
                    double cos1 = cos((2*x+1)*u*M_PI/16.0);
                    double cos2 = cos((2*y+1)*v*M_PI/16.0);
                    sum += cu * cv * block[u][v] * cos1 * cos2;
                }
            }
            temp[x][y] = 0.25 * sum;
        }
    }
    
    memcpy(block, temp, sizeof(temp));
}

// Simple XOR encryption untuk password
void xor_encrypt(uint8_t* data, size_t length, const char* password) {
    size_t pass_len = strlen(password);
    if (pass_len == 0) return;
    
    for (size_t i = 0; i < length; i++) {
        data[i] ^= password[i % pass_len];
    }
}

SteganographyResult encode_lsb_dct(const uint8_t* image_data, size_t image_size,
                                  const uint8_t* message, size_t message_length,
                                  const char* password) {
    SteganographyResult result = {0};
    
    if (!image_data || !message) {
        result.success = false;
        result.error_message = "Invalid input data";
        return result;
    }
    
    // Enkripsi pesan dengan password
    uint8_t* encrypted_message = malloc(message_length);
    if (!encrypted_message) {
        result.success = false;
        result.error_message = "Memory allocation failed";
        return result;
    }
    
    memcpy(encrypted_message, message, message_length);
    xor_encrypt(encrypted_message, message_length, password);
    
    // Hitung kapasitas maksimal
    size_t max_capacity = get_max_capacity(image_data, image_size);
    if (message_length + 8 > max_capacity) { // +8 untuk header
        free(encrypted_message);
        result.success = false;
        result.error_message = "Message too large for image capacity";
        return result;
    }
    
    // TODO: Implementasi lengkap LSB + DCT
    // Untuk sekarang return dummy result
    result.success = true;
    result.data = malloc(image_size);
    memcpy(result.data, image_data, image_size);
    result.data_length = image_size;
    result.width = 0; // Set default values
    result.height = 0;
    
    free(encrypted_message);
    return result;
}

SteganographyResult decode_lsb_dct(const uint8_t* image_data, size_t image_size,
                                  const char* password) {
    SteganographyResult result = {0};
    
    if (!image_data) {
        result.success = false;
        result.error_message = "Invalid image data";
        return result;
    }
    
    // TODO: Implementasi decode LSB + DCT
    // Untuk sekarang return dummy result
    const char* demo_message = "Decoded secret message";
    size_t message_length = strlen(demo_message);
    
    uint8_t* decoded_message = malloc(message_length + 1);
    if (!decoded_message) {
        result.success = false;
        result.error_message = "Memory allocation failed";
        return result;
    }
    
    strcpy((char*)decoded_message, demo_message);
    
    // Dekripsi dengan password
    xor_encrypt(decoded_message, message_length, password);
    
    result.success = true;
    result.data = decoded_message;
    result.data_length = message_length;
    result.width = 0;
    result.height = 0;
    
    return result;
}

void free_steganography_result(SteganographyResult* result) {
    if (result && result->data) {
        free(result->data);
        result->data = NULL;
        result->data_length = 0;
    }
    if (result && result->error_message) {
        free(result->error_message);
        result->error_message = NULL;
    }
}

size_t get_max_capacity(const uint8_t* image_data, size_t image_size) {
    // Asumsi 3 bytes per pixel (RGB) dan 1 bit per pixel untuk LSB
    if (image_size < 100) return 0; // Minimum image size
    
    size_t pixel_count = image_size / 3;
    return (size_t)(pixel_count * MAX_CAPACITY_FACTOR);
}