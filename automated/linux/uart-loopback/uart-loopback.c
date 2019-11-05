// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2019 Schneider Electric
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <string.h>

pthread_t thr_read;
volatile int read_thread_ready = 0;
const char* program_name;
const char* output_device = NULL;
const char* input_device = NULL;
int transfer_size = 1;
int auto_increment = 0;
int ignore_errors = 0;
int verbose = 0;
int results = 0;
int current_write_data = 0;
int transfer_by_byte = 0;
int no_delay = 0;
int error = 0;

void uart_write (int length)
{
	int writefd, i;
	char data = 0;
	char buffer[length + 1];

	for (i=0; i<length; i++, data++) {
		if (data > 9)
			data = 0;

		buffer[i] = '0' + data;
	}

	buffer[length] = '\0';

	writefd = open(output_device, O_WRONLY);

	if (writefd < 0) {
		perror("Error opening write device\n");
		exit(1);
	}

	tcflush(writefd, TCOFLUSH);

	if (verbose)
		printf("Writing to device: %s\n", output_device);

	if (verbose)
		printf("Write: %s\n", buffer);

	if (write(writefd, &buffer, length) != length)
		perror("Error when writing\n");

	if (verbose)
		printf("Writing end\n");

	close(writefd);
}

void uart_write_byte (int length)
{
	int writefd, i;
	char data;

	writefd = open(output_device, O_WRONLY);

	if (writefd < 0) {
		perror("Error opening write device\n");
		exit(1);
	}

	tcflush(writefd, TCOFLUSH);

	if (verbose)
		printf("Writing to device: %s\n", output_device);

	for (i=0; i<length; i++, current_write_data++) {
		if (current_write_data > 9)
			current_write_data = 0;

		data = '0' + current_write_data;

		if (verbose)
			printf("Write: %c\n", data);

		write(writefd, &data, 1);

		/* Give read thread a chance */
		struct timespec tim, tim2;
		tim.tv_sec = 0;
		tim.tv_nsec = 1000000L; /* 1ms */
		nanosleep(&tim , &tim2);
	}

	if (verbose)
		printf("Writing end\n");

	close(writefd);
}

void* uart_read_byte (void* arg)
{
	int readfd, read_len, total_len, i;
	char data;
	int expected_read_length;

	if (auto_increment)
		expected_read_length = (transfer_size * (transfer_size + 1)) / 2;
	else
		expected_read_length = transfer_size;

	readfd = open(input_device, O_RDONLY);

	if (readfd < 0) {
		perror("Error opening read device\n");
		pthread_exit(NULL);
	}

	if (verbose)
		printf("Reading from device: %s\n", input_device);

	tcflush(readfd, TCIFLUSH);

	/* Thread is ready for data to be written */
	read_thread_ready = 1;

	for (i=0, total_len=0; total_len<expected_read_length; i++) {
		if (i > 9)
			i = 0;

		read_len = read(readfd, &data, 1);

		if (read_len < 0) {
			perror("Read error\n");
			break;
		}

		total_len += read_len;

		if (total_len <= expected_read_length) {
			if (verbose)
				printf ("Read: %c / 0x%X\n", data, data);

			/* Check for expected data */
			if (i != (int) strtol (&data, NULL, 10)) {
				if (verbose) {
					printf("Erroneous Data Received\n");
					printf("Read %c instead of %c\n", data, ('0' + i));
				}
				error = 1;

				if (!ignore_errors)
					break;
			}
		}

		/* TODO Add timeout */
		if (total_len > expected_read_length)
			break;
	}

	if (verbose)
		printf ("Reading end\n");

	close (readfd);
	pthread_exit(NULL);
}

void print_usage (FILE* stream, int exit_code)
{
	fprintf (stream, "Usage: %s options\n", program_name);
	fprintf (stream,
		" -h --help             Display this usage information.\n"
		" -o --output device    Serial device to write out from.\n"
		" -i --input device     Serial device to read in from.\n"
		" -s --size bytes       Number of bytes to transfer.\n"
		" -v --verbose          Displays the test outputs.\n"
		" -r --results          Dispays the test results regardless of verbose setting.\n"
		" -a --auto-increment   Transfer size increments automatically up to the maximum transfer size.\n"
		" -I --ignore-errors    Carry on with tests regardless of errors.\n"
		" -b --transfer-by-byte Test data transferred byte at a time.\n"
		" -n --no-delay         Removes the 1 second time delay between each automatic incremental transfer.\n");
	exit (exit_code);
}

int main (int argc, char* argv[])
{
	int next_option, length;
	const char* const short_options = "ho:i:s:vraIbn";
	const struct option long_options[] = {
		{ "help", 0, NULL, 'h' },
		{ "out", 1, NULL, 'o' },
		{ "in", 1, NULL, 'i' },
		{ "size", 1, NULL, 's' },
		{ "verbose", 0, NULL, 'v' },
		{ "results", 0, NULL, 'r' },
		{ "auto-increment", 0, NULL, 'a' },
		{ "ignore-errors", 0, NULL, 'I' },
		{ "transfer-by-byte", 0, NULL, 'b' },
		{ "no-delay", 0, NULL, 'n' },
		{ NULL, 0, NULL, 0 }
	};

	program_name = argv[0];

	do {
		next_option = getopt_long (argc, argv, short_options,
		long_options, NULL);

		switch (next_option)
		{
		case 'h': /* -h or --help */
			print_usage (stdout, 0);

		case 'o': /* -o or --output */
			output_device = optarg;
		break;

		case 'i': /* -i or --input */
			input_device = optarg;
		break;

		case 's': /* -s or --size */
			transfer_size = (int) strtol (optarg, NULL, 10);
		break;

		case 'v': /* -v or --verbose */
			verbose = 1;
		break;

		case 'r': /* -r or --results */
			results = 1;
		break;

		case 'a': /* -a or --auto-increment */
			auto_increment = 1;
		break;

		case 'I': /* -I or --ignore-errors */
			ignore_errors = 1;
		break;

		case 'b': /* -b or --transfer-by-byte */
			transfer_by_byte = 1;
		break;

		case 'n': /* -n or --no-delay */
			no_delay = 1;
		break;

		case '?': /* Invalid option */
			print_usage (stderr, 1);

		case -1: /* Done with options */
			break;

		default: /* Something unexpected */
			abort ();
		}
	}
	while (next_option != -1);

	/* Set defaults */
	if (output_device == NULL)
		output_device = "/dev/ttyAMA1";

	if (input_device == NULL)
		input_device = "/dev/ttyAMA3";

	if (verbose)
		printf ("output_device: %s\ninput_device: %s\ntransfer_size: %d\n", output_device, input_device, transfer_size);
/*
	struct timespec tim, tim2;
	tim.tv_sec = 1;
	tim.tv_nsec = 0;
	nanosleep(&tim , &tim2);
*/
	/* Start read thread */
	pthread_create (&thr_read, NULL, uart_read_byte, NULL);

	/* Make sure read thread is ready before writing starts */
	while (!read_thread_ready)
		;

	if (auto_increment) {
		for (length=1; length<=transfer_size; length++) {
			if (!error || ignore_errors) {
				if (transfer_by_byte)
					uart_write_byte(length);
				else
					uart_write(length);
			}

			/* Long wait between tests */
			if (!no_delay) {
				struct timespec tim, tim2;
				tim.tv_sec = 0;
				tim.tv_nsec = 100000000L; /* 100ms */
				nanosleep(&tim , &tim2);
			}
		}
	} else {
		if (transfer_by_byte)
			uart_write_byte(transfer_size);
		else
			uart_write(transfer_size);
	}

	pthread_join(thr_read, NULL);

	if (error) {
		if (results)
			fprintf(stderr, "Test Complete with Errors\n");
		return -1;
	} else {
		if (results)
			printf(".");
		return 0;
	}
}
