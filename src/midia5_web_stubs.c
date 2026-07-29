/* TinySoundFont-based MIDI backend for Emscripten builds of Allegro-Legacy.
   Legacy's own MIDI player does all sequencing (driven by the web timer
   pumps) and streams raw MIDI bytes into _midia5_platform_send_data; we
   parse them and drive a TSF softsynth rendered into an A5 audio stream.
   The stream is refilled via _all_web_synth_pump, weak-hooked from
   Legacy's _all_web_sound_pump. Soundfont: data/soundfont.sf2. */
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <allegro5/allegro.h>
#include <allegro5/allegro_audio.h>

#define TSF_IMPLEMENTATION
#include "tsf.h"

typedef struct MIDIA5_OUTPUT_HANDLE MIDIA5_OUTPUT_HANDLE;

#define WEB_SYNTH_FREQ        44100
#define WEB_SYNTH_BUFS        4
#define WEB_SYNTH_BUFLEN      512
#define WEB_SYNTH_GAIN_DB     -13.0f   /* synth-internal headroom */
#define WEB_SYNTH_STREAM_GAIN 1.00f   /* background music level */

static tsf * web_tsf = NULL;
static ALLEGRO_AUDIO_STREAM * web_synth_stream = NULL;

/* raw MIDI byte-stream parser state (supports running status) */
static int st_status = 0;
static int st_d1 = -1;

int _midia5_get_platform_output_device_count(void)
{
    return 1;
}

const char * _midia5_get_platform_output_device_name(int device)
{
    (void)device;
    return "TinySoundFont";
}

void * _midia5_init_output_platform_data(MIDIA5_OUTPUT_HANDLE * hp, int device)
{
    (void)hp;
    (void)device;
    if(!web_tsf)
    {
        web_tsf = tsf_load_filename("data/soundfont.sf2");
        if(!web_tsf)
        {
            fprintf(stderr, "TSF: soundfont load failed\n");
            return NULL;
        }
        tsf_set_output(web_tsf, TSF_STEREO_INTERLEAVED, WEB_SYNTH_FREQ, WEB_SYNTH_GAIN_DB);
        tsf_channel_set_bank_preset(web_tsf, 9, 128, 0); /* GM percussion */
    }
    if(!web_synth_stream)
    {
        web_synth_stream = al_create_audio_stream(WEB_SYNTH_BUFS, WEB_SYNTH_BUFLEN, WEB_SYNTH_FREQ, ALLEGRO_AUDIO_DEPTH_INT16, ALLEGRO_CHANNEL_CONF_2);
        if(web_synth_stream)
        {
            al_attach_audio_stream_to_mixer(web_synth_stream, al_get_default_mixer());
            al_set_audio_stream_gain(web_synth_stream, WEB_SYNTH_STREAM_GAIN);
            al_set_audio_stream_playing(web_synth_stream, true);
        }
        else
        {
            fprintf(stderr, "TSF: stream create FAILED\n");
        }
    }
    return (void *)web_tsf;
}

void _midia5_free_output_platform_data(MIDIA5_OUTPUT_HANDLE * hp)
{
    (void)hp;
    if(web_tsf)
    {
        tsf_note_off_all(web_tsf);
    }
    st_status = 0;
    st_d1 = -1;
}

static void web_midi_message(int status, int d1, int d2)
{
    int ch = status & 0x0F;

    switch(status & 0xF0)
    {
        case 0x80:
        {
            tsf_channel_note_off(web_tsf, ch, d1);
            break;
        }
        case 0x90:
        {
            if(d2 > 0)
            {
                tsf_channel_note_on(web_tsf, ch, d1, (float)d2 / 127.0f);
            }
            else
            {
                tsf_channel_note_off(web_tsf, ch, d1);
            }
            break;
        }
        case 0xB0:
        {
            tsf_channel_midi_control(web_tsf, ch, d1, d2);
            break;
        }
        case 0xC0:
        {
            tsf_channel_set_presetnumber(web_tsf, ch, d1, (ch == 9));
            break;
        }
        case 0xE0:
        {
            tsf_channel_set_pitchwheel(web_tsf, ch, (d2 << 7) | d1);
            break;
        }
        default:
        {
            break;
        }
    }
}

void _midia5_platform_send_data(MIDIA5_OUTPUT_HANDLE * hp, int data)
{
    (void)hp;
    if(!web_tsf)
    {
        return;
    }
    data &= 0xFF;
    if(data & 0x80)
    {
        if(data >= 0xF0)
        {
            /* sysex / realtime: no channel voice state, just resync */
            st_status = 0;
            st_d1 = -1;
            return;
        }
        st_status = data;
        st_d1 = -1;
        return;
    }
    if(!st_status)
    {
        return;
    }
    switch(st_status & 0xF0)
    {
        case 0xC0: /* program change: 1 data byte */
        {
            web_midi_message(st_status, data, 0);
            break;
        }
        case 0xD0: /* channel aftertouch: 1 data byte, ignored */
        {
            break;
        }
        default: /* 2 data bytes */
        {
            if(st_d1 < 0)
            {
                st_d1 = data;
            }
            else
            {
                web_midi_message(st_status, st_d1, data);
                st_d1 = -1;
            }
            break;
        }
    }
}

void _midia5_platform_reset_output_device(MIDIA5_OUTPUT_HANDLE * hp)
{
    (void)hp;
    if(web_tsf)
    {
        tsf_note_off_all(web_tsf);
    }
    st_status = 0;
    st_d1 = -1;
}

bool _midia5_platform_set_output_gain(MIDIA5_OUTPUT_HANDLE * hp, float gain)
{
    (void)hp;
    if(web_synth_stream)
    {
        al_set_audio_stream_gain(web_synth_stream, WEB_SYNTH_STREAM_GAIN * gain);
        return true;
    }
    return false;
}

/* Called from Legacy's _all_web_sound_pump (weak hook): refill any ready
   synth-stream fragments with freshly rendered audio. */
void _all_web_synth_pump(void)
{
    void * fragment;

    if(!web_tsf || !web_synth_stream)
    {
        return;
    }
    for(;;)
    {
        fragment = al_get_audio_stream_fragment(web_synth_stream);
        if(!fragment)
        {
            break;
        }
        tsf_render_short(web_tsf, (short *)fragment, WEB_SYNTH_BUFLEN, 0);
        al_set_audio_stream_fragment(web_synth_stream, fragment);
    }
}
