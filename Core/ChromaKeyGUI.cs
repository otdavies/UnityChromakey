using UnityEngine;
using UnityEditor;
using System.Linq;

class ChromaKeyGUI : BaseShaderGUI
{
    class ChromaKeyProperties
    {
        public MaterialProperty mainTex;
        public MaterialProperty keyColor;
        public MaterialProperty tintColor;
        public MaterialProperty colorCutoff;
        public MaterialProperty colorFeathering;
        public MaterialProperty maskFeathering;
        public MaterialProperty despill;
        public MaterialProperty despillLuminanceAdd;
        public MaterialProperty isEnabled;

        public ChromaKeyProperties(MaterialProperty[] properties)
        {
            mainTex = BaseShaderGUI.FindProperty("_MainTex", properties, false);
            keyColor = BaseShaderGUI.FindProperty("_KeyColor", properties, false);
            tintColor = BaseShaderGUI.FindProperty("_TintColor", properties, false);
            colorCutoff = BaseShaderGUI.FindProperty("_ColorCutoff", properties, false);
            colorFeathering = BaseShaderGUI.FindProperty("_ColorFeathering", properties, false);
            maskFeathering = BaseShaderGUI.FindProperty("_MaskFeathering", properties, false);
            despill = BaseShaderGUI.FindProperty("_Despill", properties, false);
            despillLuminanceAdd = BaseShaderGUI.FindProperty("_DespillLuminanceAdd", properties, false);
            isEnabled = BaseShaderGUI.FindProperty("_IsEnabled", properties, false);
        }
    }

    private ChromaKeyProperties m_Properties;
    private readonly int[] m_SampleSize = { 32, 32 };

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        m_Properties = new ChromaKeyProperties(properties);
        Material material = materialEditor.target as Material;

        if (material == null)
            return;

        DrawChromaKeyGUI(materialEditor, material);
    }

    private void DrawChromaKeyGUI(MaterialEditor materialEditor, Material material)
    {
        // Effect toggle at the top
        EditorGUILayout.Space(5);
        materialEditor.ShaderProperty(m_Properties.isEnabled, "Enable Chroma Key Effect");
        EditorGUILayout.Space(5);

        // Main settings section
        using (new EditorGUILayout.VerticalScope(EditorStyles.helpBox))
        {
            EditorGUILayout.LabelField("Main Settings", EditorStyles.boldLabel);
            materialEditor.TextureProperty(m_Properties.mainTex, "Source Texture", true);

            if (GUILayout.Button("Auto-Detect Green Screen Color"))
            {
                DetectKeyColor(material);
            }
            EditorGUILayout.LabelField("Color Adjustment", EditorStyles.boldLabel);
            materialEditor.ShaderProperty(m_Properties.keyColor, "Key Color");
            materialEditor.ShaderProperty(m_Properties.tintColor, "Tint Color");
        }

        EditorGUI.BeginDisabledGroup(!m_Properties.isEnabled.floatValue.Equals(1.0f));

        // Key controls section
        EditorGUILayout.Space(10);
        using (new EditorGUILayout.VerticalScope(EditorStyles.helpBox))
        {
            EditorGUILayout.LabelField("Key Controls", EditorStyles.boldLabel);
            materialEditor.ShaderProperty(m_Properties.colorCutoff, "Background Removal Strength");
            materialEditor.ShaderProperty(m_Properties.colorFeathering, "Edge Softness");
        }

        // Fine-tuning section
        EditorGUILayout.Space(10);
        using (new EditorGUILayout.VerticalScope(EditorStyles.helpBox))
        {
            materialEditor.ShaderProperty(m_Properties.maskFeathering, "Mask Smoothing");
            materialEditor.ShaderProperty(m_Properties.despill, "Spill Removal");
            materialEditor.ShaderProperty(m_Properties.despillLuminanceAdd, "Preserve Brightness");
        }

        EditorGUI.EndDisabledGroup();
    }

    private void DetectKeyColor(Material material)
    {
        var mainTex = material.GetTexture("_MainTex") as Texture2D;
        if (mainTex == null) return;

        RenderTexture tmp = RenderTexture.GetTemporary(
            m_SampleSize[0],
            m_SampleSize[1],
            0,
            RenderTextureFormat.Default,
            RenderTextureReadWrite.Linear
        );

        Graphics.Blit(mainTex, tmp);
        RenderTexture.active = tmp;

        Texture2D sample = new Texture2D(m_SampleSize[0], m_SampleSize[1], TextureFormat.RGB24, false);
        sample.ReadPixels(new Rect(0, 0, m_SampleSize[0], m_SampleSize[1]), 0, 0);
        sample.Apply();

        Color[] pixels = sample.GetPixels();

        var greenPixels = pixels
            .Where(c => c.g > c.r * 1.5f && c.g > c.b * 1.5f)
            .OrderByDescending(c => c.g)
            .Take(pixels.Length / 4)
            .ToList();

        if (greenPixels.Any())
        {
            Color avgColor = new Color(
                greenPixels.Average(c => c.r),
                greenPixels.Average(c => c.g),
                greenPixels.Average(c => c.b),
                1f
            );

            material.SetColor("_KeyColor", avgColor);
            EditorUtility.SetDirty(material);
        }

        RenderTexture.active = null;
        RenderTexture.ReleaseTemporary(tmp);
    }
}