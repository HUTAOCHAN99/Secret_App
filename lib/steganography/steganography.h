// secret_app/lib/steganography/steganography.h
#ifndef STEGANOGRAPHY_H
#define STEGANOGRAPHY_H

#include <stdint.h>
#include <stdbool.h>

// Struktur untuk hasil steganografi
typedef struct {
    bool success;
    char* error_message;
    uint8_t* data;
    size_t data_length;
    int width;
    int height;
} SteganographyResult;

// Fungsi untuk encode pesan ke dalam gambar
SteganographyResult encode_lsb_dct(const uint8_t* image_data, size_t image_size,
                                  const uint8_t* message, size_t message_length,
                                  const char* password);

// Fungsi untuk decode pesan dari gambar
SteganographyResult decode_lsb_dct(const uint8_t* image_data, size_t image_size,
                                  const char* password);

// Fungsi untuk membersihkan memory
void free_steganography_result(SteganographyResult* result);

// Fungsi untuk mengecek kapasitas maksimal
size_t get_max_capacity(const uint8_t* image_data, size_t image_size);

#endif // STEGANOGRAPHY_H