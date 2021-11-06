/** 
 **  Dreamlike ReShade
 **  By Toxijuice
 ** 
 **  NOTE - Many of the functions were derived from other sources
 **  I've done my best to link to where they are from
 ** 
 **  This likely could have been done with existing
 **  ReShade shaders, but this is my first time
 **  using ReShade and I wanted to see how it worked.
 **
 **/


#include "ReShade.fxh"

#define bloomBlurSamples 20

uniform float brightness = 0.75;
uniform float exposure = 1.50; 
uniform float saturation = -0.1;

uniform float bloomStrength = 0.05;
uniform float bloomBlurSize = 40;
uniform float bloomSaturation = 0.5;

uniform float3 lift  = float3(0.990000, 0.990000, 1.000000);
uniform float3 gamma = float3(1.200000, 1.200000, 1.330000);
uniform float3 gain  = float3(1.200000, 1.150000, 1.000000);


texture lightTex01{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RGBA16F;
};
texture tex01{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RGBA16F;
  MipLevels = 5;
};
texture tex02{
	Width = BUFFER_WIDTH/32;
	Height = BUFFER_HEIGHT/32;
	Format = RGBA16F;
};
texture tex03{
	Width = BUFFER_WIDTH/16;
	Height = BUFFER_HEIGHT/16;
	Format = RGBA16F;
};
texture tex04{
	Width = BUFFER_WIDTH/8;
	Height = BUFFER_HEIGHT/8;
	Format = RGBA16F;
};
texture tex05{
	Width = BUFFER_WIDTH/4;
	Height = BUFFER_HEIGHT/4;
	Format = RGBA16F;
};
texture tex06{
	Width = BUFFER_WIDTH/2;
	Height = BUFFER_HEIGHT/2;
	Format = RGBA16F;
};

sampler SamplerLight01 { Texture = lightTex01; };
sampler BloomSampler01 { Texture = tex01; };
sampler BloomSampler02 { Texture = tex02; };
sampler BloomSampler03 { Texture = tex03; };
sampler BloomSampler04 { Texture = tex04; };
sampler BloomSampler05 { Texture = tex05; };
sampler BloomSampler06 { Texture = tex06; };

// Derived from https://stackoverflow.com/a/17897228
float3 RGB2HSV(float3 c){
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Derived from https://stackoverflow.com/a/17897228
float3 HSV2RGB(float3 c){
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float3 AddSaturation(float3 rgb, float saturation){
  float3 hsv = RGB2HSV(rgb);
  hsv.y = saturate(hsv.y + saturation);

  return HSV2RGB(hsv);
}

// Derived from Martijn Steinrucken
// https://www.youtube.com/channel/UCcAlTqd9zID6aNX3TzwxJXg
float N21(float2 p){
  p = frac(p*float2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return frac(p.x*p.y);
}

// Derived from https://www.youtube.com/watch?v=0flY11lVCwY
float3 Blur(sampler2D tex, float2 uv){
  float3 col = 0;
  float2 blur = (BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT) * bloomBlurSize;

  float a = N21(uv) * 6.2831;
  for(int i = 0; i < bloomBlurSamples; i++){
    float2 offs = float2(sin(a), cos(a)) * blur;
    float d = frac(sin((i+1)*546.0)*5424.0);
    d = sqrt(d);
    offs *= d;
    col += tex2D(tex, uv + offs).rgb;
    a++;
  }

  col /= bloomBlurSamples;

  return col;
}


// Derived from http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
float3 GammaToLinear(float3 sRGB){
  return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}

// Derived from http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
float3 LinearToGamma(float3 RGB){
  float3 S1 = sqrt(RGB);
  float3 S2 = sqrt(S1);
  float3 S3 = sqrt(S2);
  float3 sRGB = 0.585122381 * S1 + 0.783140355 * S2 - 0.368262736 * S3;

  return sRGB;
}

// Derived from https://github.com/crosire/reshade-shaders/blob/master/Shaders/LiftGammaGain.fx
float3 LGG( float3 col ){
	col = col * (1.5-0.5 * lift) + 0.5 * lift - 0.5;
	col = saturate(col);
	col *= gain; 
	col = pow(col, 1.0 / gamma); 
	return saturate(col);
}

// Derived from https://github.com/dmnsgn/glsl-tone-map/blob/master/aces.glsl
float3 ACESTonemap(float3 x){
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

float GetLuminosity(float3 col){
  return (col.r * 0.3) + (col.g * 0.59) + (col.b * 0.11);
}

float3 Light(sampler2D tex, float2 uv){
  float3 col = tex2D(tex, uv);
  col = GammaToLinear(col) * brightness;
  col=1.0-exp(-col*exposure);
  col = ACESTonemap(col);
  
  return col; 
}

float3 Main(sampler2D tex, float2 uv){
  float3 col = tex2D(tex, uv);
  float3 bloom = tex2D(BloomSampler06, uv).rgb;
  bloom = bloom + bloom * bloom * 3;
  bloom = AddSaturation(bloom, bloomSaturation);
  col = AddSaturation(col, saturation);
  col = lerp(col, col + bloom, bloomStrength);
  col = LinearToGamma(col);
  col = LGG(col);

  return col; 
}


void LightPass0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = float4(Light(ReShade::BackBuffer, uv), 1.0);
}

void BloomPass0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = tex2D(ReShade::BackBuffer, uv);
  float bloomArea = 1-smoothstep(GetLuminosity((col * col * col)/(brightness + 0.001)), 0.2, 0.3);
  col = col * bloomArea;
}

void BloomPass1(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = tex2Dlod(BloomSampler01, float4(uv,0,6));
}

void BloomPass2(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = Blur(BloomSampler02, uv);
  col.a = 1;
}

void BloomPass3(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = Blur(BloomSampler03, uv);
  col.a = 1;
}

void BloomPass4(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = Blur(BloomSampler04, uv);
  col.a = 1;
}

void BloomPass5(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 col : SV_Target){
  col = Blur(BloomSampler05, uv);
  col.a = 1;
}


float4 Frag(float4 vpos : SV_Position, float2 uv : TexCoord) : SV_Target{
    return float4(Main(SamplerLight01, uv), 1.0);
}

technique ToxiDreamlikeHL2{

  pass LightPass0{
		VertexShader = PostProcessVS;
		PixelShader = LightPass0;
		RenderTarget = lightTex01;
	}

  pass BloomPass0{
		VertexShader = PostProcessVS;
		PixelShader = BloomPass0;
		RenderTarget = tex01;
	}

  pass BloomPass1{
		VertexShader = PostProcessVS;
		PixelShader = BloomPass1;
		RenderTarget = tex02;
	}

  pass BloomPass2{
		VertexShader = PostProcessVS;
		PixelShader = BloomPass2;
		RenderTarget = tex03;
	}

  pass BloomPass3{
		VertexShader = PostProcessVS;
		PixelShader = BloomPass3;
		RenderTarget = tex04;
	}

  pass BloomPass4{
		VertexShader = PostProcessVS;
		PixelShader = BloomPass4;
		RenderTarget = tex05;
	}

  pass BloomPass6{
		VertexShader = PostProcessVS;
		PixelShader = BloomPass5;
		RenderTarget = tex06;
	}
  
  pass FinalPass{
      VertexShader = PostProcessVS;
      PixelShader = Frag;
  }
  
}