//
//  SDUIVariant_VerticalListAsync.swift
//  Encore
//
//  Vertical list async advertiser flow: intro → offers → email capture → IAP.
//  Full-screen cover with multi-state navigation and async image loading.
//
//  Usage: Add `-SDUIDevVariant verticalListAsync` to Xcode scheme launch arguments.
//

#if DEBUG
enum SDUIVariant_VerticalListAsync {
    static let json = """
{
  "version": "1.0.0",
  "presentationStyle": "fullScreenCover",
  "presentationDetents": [1.0],
  "cornerRadius": 0,
  "showDragIndicator": false,
  "initialState": "intro",
  "autoSelectFirstOffer": true,
  "stateDetents": {
    "intro": [1.0],
    "offers": [1.0],
    "capture": [1.0],
    "iap": [0.45]
  },
  "stateActions": {
    "iap": {
      "onEnter": {
        "type": "triggerIAP",
        "onSuccessState": "close",
        "onCancelAction": "capture"
      }
    }
  },
  "root": {
    "conditional": {
      "condition": { "stateEquals": "intro" },
      "ifTrue": {
        "zStack": {
          "alignment": "top",
          "children": [
            {
              "gradient": {
                "direction": "topToBottom",
                "colors": [
                  { "color": { "appearance": "accent" }, "opacity": 0.6 },
                  { "color": { "appearance": "background" }, "opacity": 1.0 }
                ],
                "style": { "ignoresSafeArea": true }
              }
            },
            {
              "vStack": {
                "spacing": 0,
                "children": [
                  {
                    "hStack": {
                      "children": [
                        { "spacer": {} },
                        {
                          "button": {
                            "content": {
                              "zStack": {
                                "alignment": "center",
                                "children": [
                                  { "shape": { "type": "circle", "fillColor": { "hex": "#FFFFFF" }, "style": { "frame": { "width": 32, "height": 32 }, "opacity": 0.4 } } },
                                  { "systemImage": { "systemName": "xmark", "font": { "size": 11, "weight": "bold" }, "color": { "appearance": "onBackground" } } }
                                ]
                              }
                            },
                            "action": "close",
                            "style": { "padding": { "top": 56, "trailing": 10, "bottom": 4 } }
                          }
                        }
                      ]
                    }
                  },
                  { "spacer": { "style": { "frame": { "minHeight": 10 } } } },
                  {
                    "hStack": {
                      "spacing": 10,
                      "alignment": "center",
                      "children": [
                        {
                          "forEach": {
                            "dataSource": "offers",
                            "limit": 4,
                            "itemTemplate": {
                              "asyncImage": {
                                "urlBinding": "offerLogoImage",
                                "contentMode": "fit",
                                "placeholderColor": { "semantic": "tertiarySystemFill" },
                                "style": { "frame": { "width": 52, "height": 52 }, "cornerRadius": 12, "clipped": true }
                              }
                            }
                          }
                        }
                      ],
                      "style": { "padding": { "leading": 24, "trailing": 24, "bottom": 24 } }
                    }
                  },
                  {
                    "vStack": {
                      "spacing": 12,
                      "alignment": "center",
                      "children": [
                        { "text": { "text": "Someone wants to gift you ${premiumTierName}", "font": { "size": 28, "weight": "semibold" }, "color": { "appearance": "onBackground" }, "multilineAlignment": "center", "lineHeight": 1.05 } },
                        { "text": { "text": "${appName}'s brand partner is offering to pay for your subscription. Just share your email.", "font": { "size": 15, "weight": "regular" }, "color": { "appearance": "muted" }, "multilineAlignment": "center" } }
                      ],
                      "style": {
                        "padding": { "leading": 24, "trailing": 24, "bottom": 24 },
                        "frame": { "maxWidth": "infinity" }
                      }
                    }
                  },
                  {
                    "group": {
                      "content": {
                        "hStack": {
                          "spacing": 16,
                          "alignment": "center",
                          "children": [
                            {
                              "appIcon": {
                                "style": { "frame": { "width": 48, "height": 48 }, "cornerRadius": 12 }
                              }
                            },
                            {
                              "vStack": {
                                "spacing": 2,
                                "alignment": "leading",
                                "children": [
                                  { "text": { "text": "${appName}", "font": { "size": 16, "weight": "semibold" }, "color": { "appearance": "onBackground" } } },
                                  { "text": { "text": "${trialValue} ${trialUnit} access", "font": { "size": 13, "weight": "regular" }, "color": { "appearance": "muted" } } }
                                ]
                              }
                            },
                            { "spacer": {} },
                            {
                              "vStack": {
                                "spacing": 2,
                                "alignment": "trailing",
                                "children": [
                                  { "text": { "text": "$0", "font": { "size": 28, "weight": "bold" }, "color": { "appearance": "accent" } } },
                                  { "text": { "text": "${subscriptionPrice}/mo", "font": { "size": 12, "weight": "regular" }, "color": { "appearance": "muted" }, "strikethrough": true } }
                                ]
                              }
                            }
                          ],
                          "style": {
                            "padding": { "top": 14, "leading": 16, "bottom": 14, "trailing": 16 },
                            "backgroundColor": { "appearance": "surface" },
                            "cornerRadius": 16
                          }
                        }
                      },
                      "style": { "padding": { "leading": 24, "trailing": 24 } }
                    }
                  },
                  {
                    "vStack": {
                      "spacing": 16,
                      "alignment": "center",
                      "children": [
                        { "text": { "text": "How it works", "font": { "size": 15, "weight": "semibold" }, "color": { "appearance": "onBackground" } } },
                        {
                          "hStack": {
                            "spacing": 12,
                            "alignment": "top",
                            "children": [
                              {
                                "vStack": {
                                  "spacing": 10,
                                  "alignment": "center",
                                  "children": [
                                    { "text": { "text": "1", "font": { "size": 14, "weight": "bold" }, "color": { "appearance": "accent" }, "style": { "padding": { "horizontal": 10, "vertical": 4 }, "cornerRadius": 6, "backgroundColor": { "appearance": "surface" } } } },
                                    { "text": { "text": "Pick a brand sponsor", "font": { "size": 14, "weight": "medium" }, "color": { "appearance": "onBackground" }, "multilineAlignment": "center" } }
                                  ],
                                  "style": {
                                    "padding": { "top": 16, "bottom": 16 },
                                    "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" },
                                    "cornerRadius": 14,
                                    "backgroundColor": { "appearance": "surface" },
                                    "shadow": { "color": { "hex": "#000000" }, "radius": 4, "x": 0, "y": 2, "opacity": 0.1 }
                                  }
                                }
                              },
                              {
                                "vStack": {
                                  "spacing": 10,
                                  "alignment": "center",
                                  "children": [
                                    { "text": { "text": "2", "font": { "size": 14, "weight": "bold" }, "color": { "appearance": "accent" }, "style": { "padding": { "horizontal": 10, "vertical": 4 }, "cornerRadius": 6, "backgroundColor": { "appearance": "surface" } } } },
                                    { "text": { "text": "Activate your gifted ${premiumTierName}", "font": { "size": 14, "weight": "medium" }, "color": { "appearance": "onBackground" }, "multilineAlignment": "center" } }
                                  ],
                                  "style": {
                                    "padding": { "top": 16, "bottom": 16 },
                                    "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" },
                                    "cornerRadius": 14,
                                    "backgroundColor": { "appearance": "surface" },
                                    "shadow": { "color": { "hex": "#000000" }, "radius": 4, "x": 0, "y": 2, "opacity": 0.1 }
                                  }
                                }
                              }
                            ],
                            "style": { "fixedSize": { "vertical": true } }
                          }
                        }
                      ],
                      "style": { "padding": { "top": 28, "leading": 24, "trailing": 24 } }
                    }
                  },
                  {
                    "vStack": {
                      "spacing": 14,
                      "alignment": "center",
                      "children": [
                        {
                          "button": {
                            "content": { "text": { "text": "Get Free ${premiumTierName}", "font": { "size": 17, "weight": "bold" }, "color": { "appearance": "onAccent" } } },
                            "action": { "type": "setState", "setState": "offers" },
                            "style": { "frame": { "maxWidth": "infinity" }, "padding": { "top": 18, "bottom": 18 }, "cornerRadius": 28, "backgroundColor": { "appearance": "accent" }, "shadow": { "color": { "appearance": "accent" }, "radius": 12, "x": 0, "y": 4, "opacity": 0.4 } }
                          }
                        },
                        {
                          "button": {
                            "content": { "text": { "text": "No Thanks", "font": { "size": 15, "weight": "semibold" }, "color": { "appearance": "muted" } } },
                            "action": "close"
                          }
                        }
                      ],
                      "style": { "padding": { "top": 20, "leading": 24, "trailing": 24, "bottom": 40 } }
                    }
                  }
                ],
                "style": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" }, "ignoresSafeArea": true }
              }
            }
          ]
        }
      },
      "ifFalse": {
        "conditional": {
          "condition": { "stateEquals": "offers" },
          "ifTrue": {
            "zStack": {
              "alignment": "top",
              "children": [
                {
                  "gradient": {
                    "direction": "topToBottom",
                    "colors": [
                      { "color": { "appearance": "accent" }, "opacity": 0.5 },
                      { "color": { "appearance": "background" }, "opacity": 1.0 }
                    ],
                    "style": { "ignoresSafeArea": true }
                  }
                },
                {
                  "vStack": {
                    "spacing": 0,
                    "children": [
                      {
                        "hStack": {
                          "children": [
                            {
                              "button": {
                                "content": {
                                  "zStack": {
                                    "alignment": "center",
                                    "children": [
                                      { "shape": { "type": "circle", "fillColor": { "hex": "#FFFFFF" }, "style": { "frame": { "width": 32, "height": 32 }, "opacity": 0.4 } } },
                                      { "systemImage": { "systemName": "chevron.left", "font": { "size": 14, "weight": "semibold" }, "color": { "appearance": "onBackground" } } }
                                    ]
                                  }
                                },
                                "action": { "type": "setState", "setState": "intro" },
                                "style": { "padding": { "top": 56, "leading": 16, "bottom": 8 } }
                              }
                            },
                            { "spacer": {} }
                          ]
                        }
                      },
                      {
                        "text": {
                          "text": "Choose your sponsor",
                          "font": { "size": 28, "weight": "semibold" },
                          "lineHeight": 1.05,
                          "color": { "appearance": "onBackground" },
                          "multilineAlignment": "center",
                          "style": {
                            "padding": { "top": 4, "leading": 24, "trailing": 24, "bottom": 16 },
                            "frame": { "maxWidth": "infinity" }
                          }
                        }
                      },
                      {
                        "zStack": {
                          "alignment": "bottom",
                          "children": [
                            {
                              "scrollView": {
                                "axis": "vertical",
                                "showsIndicators": false,
                                "content": {
                                  "vStack": {
                                    "spacing": 2,
                                    "lazy": true,
                                    "children": [
                                      {
                                        "forEach": {
                                          "dataSource": "offers",
                                          "itemTemplate": {
                                            "button": {
                                              "content": {
                                                "zStack": {
                                                  "children": [
                                                    {
                                                      "vStack": {
                                                        "spacing": 0,
                                                        "children": [
                                                          {
                                                            "asyncImage": {
                                                              "urlBinding": "offerPrimaryCreative",
                                                              "contentMode": "fill",
                                                              "placeholderColor": { "semantic": "tertiarySystemFill" },
                                                              "style": { "frame": { "maxWidth": "infinity" }, "cornerRadius": 16, "clipped": true }
                                                            }
                                                          },
                                                          {
                                                            "hStack": {
                                                              "spacing": 10,
                                                              "alignment": "center",
                                                              "children": [
                                                                {
                                                                  "asyncImage": {
                                                                    "urlBinding": "offerLogoImage",
                                                                    "contentMode": "fit",
                                                                    "placeholderColor": { "semantic": "tertiarySystemFill" },
                                                                    "style": { "frame": { "width": 36, "height": 36 }, "cornerRadius": 8, "clipped": true }
                                                                  }
                                                                },
                                                                {
                                                                  "vStack": {
                                                                    "spacing": 2,
                                                                    "alignment": "leading",
                                                                    "children": [
                                                                      {
                                                                        "text": {
                                                                          "text": "",
                                                                          "textBinding": "offerAdvertiserName",
                                                                          "font": { "size": 15, "weight": "semibold" },
                                                                          "color": { "semantic": "label" },
                                                                          "lineLimit": 1
                                                                        }
                                                                      },
                                                                      {
                                                                        "text": {
                                                                          "text": "",
                                                                          "textBinding": "offerDescription",
                                                                          "font": { "size": 12, "weight": "regular" },
                                                                          "color": { "semantic": "secondaryLabel" },
                                                                          "lineLimit": 1
                                                                        }
                                                                      }
                                                                    ]
                                                                  }
                                                                },
                                                                { "spacer": {} },
                                                                {
                                                                  "conditional": {
                                                                    "condition": { "isSelectedOffer": {} },
                                                                    "ifTrue": {
                                                                      "zStack": {
                                                                        "alignment": "center",
                                                                        "children": [
                                                                          { "shape": { "type": "circle", "fillColor": { "appearance": "accent" }, "style": { "frame": { "width": 26, "height": 26 } } } },
                                                                          { "systemImage": { "systemName": "checkmark", "font": { "size": 12, "weight": "bold" }, "color": { "appearance": "onAccent" } } }
                                                                        ]
                                                                      }
                                                                    },
                                                                    "ifFalse": {
                                                                      "shape": {
                                                                        "type": "circle",
                                                                        "fillColor": { "hex": "#00000000" },
                                                                        "style": { "frame": { "width": 26, "height": 26 }, "borderWidth": 2, "borderColor": { "semantic": "separator" }, "cornerRadius": 13 }
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              ],
                                                              "style": {
                                                                "padding": { "top": 10, "leading": 12, "bottom": 10, "trailing": 12 },
                                                                "backgroundColor": { "semantic": "secondarySystemGroupedBackground" }
                                                              }
                                                            }
                                                          }
                                                        ],
                                                        "style": { "frame": { "maxWidth": "infinity" }, "cornerRadius": 16, "clipped": true, "backgroundColor": { "semantic": "systemBackground" } }
                                                      }
                                                    },
                                                    {
                                                      "conditional": {
                                                        "condition": { "isSelectedOffer": {} },
                                                        "ifTrue": {
                                                          "shape": {
                                                            "type": "rectangle",
                                                            "fillColor": { "hex": "#00000000" },
                                                            "style": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" }, "cornerRadius": 16, "borderWidth": 3, "borderColor": { "appearance": "accent" } }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  ],
                                                  "style": { "frame": { "maxWidth": "infinity" }, "padding": { "all": 6 }, "shadow": { "color": { "hex": "#000000" }, "radius": 4, "x": 0, "y": 2, "opacity": 0.1 } }
                                                }
                                              },
                                              "action": { "type": "selectOffer" }
                                            }
                                          }
                                        }
                                      }
                                    ],
                                    "style": { "padding": { "top": 2, "leading": 20, "trailing": 20, "bottom": 100 } }
                                  }
                                },
                                "style": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" } }
                              }
                            },
                            {
                              "gradient": {
                                "direction": "bottomToTop",
                                "colors": [
                                  { "color": { "appearance": "background" }, "opacity": 0.9 },
                                  { "color": { "appearance": "background" }, "opacity": 0.0 }
                                ],
                                "style": { "frame": { "maxWidth": "infinity", "height": 50 } }
                              }
                            }
                          ],
                          "style": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" } }
                        }
                      },
                      {
                        "vStack": {
                          "spacing": 10,
                          "alignment": "center",
                          "children": [
                            {
                              "button": {
                                "content": { "text": { "text": "Continue with ${selectedAdvertiserName}", "font": { "size": 17, "weight": "bold" }, "color": { "appearance": "onAccent" } } },
                                "action": { "type": "setState", "setState": "capture" },
                                "style": { "frame": { "maxWidth": "infinity" }, "padding": { "top": 16, "bottom": 16 }, "cornerRadius": 28, "backgroundColor": { "appearance": "accent" }, "shadow": { "color": { "appearance": "accent" }, "radius": 12, "x": 0, "y": 4, "opacity": 0.4 } }
                              }
                            },
                            { "text": { "text": "You'll receive an exclusive ${selectedAdvertiserName} deal via email. No commitments.", "font": { "size": 12, "weight": "regular" }, "color": { "appearance": "muted" }, "multilineAlignment": "center" } }
                          ],
                          "style": { "padding": { "top": 0, "leading": 24, "trailing": 24, "bottom": 34 } }
                        }
                      }
                    ],
                    "style": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" }, "ignoresSafeArea": true }
                  }
                }
              ]
            }
          },
          "ifFalse": {
            "conditional": {
              "condition": { "stateEquals": "capture" },
              "ifTrue": {
                "zStack": {
                  "alignment": "top",
                  "children": [
                    {
                      "gradient": {
                        "direction": "topToBottom",
                        "colors": [
                          { "color": { "appearance": "accent" }, "opacity": 0.5 },
                          { "color": { "appearance": "background" }, "opacity": 1.0 }
                        ],
                        "style": { "ignoresSafeArea": true }
                      }
                    },
                    {
                      "vStack": {
                        "spacing": 0,
                        "children": [
                          {
                            "hStack": {
                              "children": [
                                {
                                  "button": {
                                    "content": {
                                      "zStack": {
                                        "alignment": "center",
                                        "children": [
                                          { "shape": { "type": "circle", "fillColor": { "hex": "#FFFFFF" }, "style": { "frame": { "width": 32, "height": 32 }, "opacity": 0.4 } } },
                                          { "systemImage": { "systemName": "chevron.left", "font": { "size": 14, "weight": "semibold" }, "color": { "appearance": "onBackground" } } }
                                        ]
                                      }
                                    },
                                    "action": { "type": "setState", "setState": "offers" },
                                    "style": { "padding": { "top": 56, "leading": 16, "bottom": 8 } }
                                  }
                                },
                                { "spacer": {} },
                                {
                                  "conditional": {
                                    "condition": { "hasValue": "iapAttempted" },
                                    "ifTrue": {
                                      "button": {
                                        "content": { "systemImage": { "systemName": "xmark", "font": { "size": 16, "weight": "semibold" }, "color": { "appearance": "muted" } } },
                                        "action": "close",
                                        "style": { "padding": { "top": 56, "trailing": 20, "bottom": 8 } }
                                      }
                                    }
                                  }
                                }
                              ]
                            }
                          },
                          {
                            "text": {
                              "text": "One Last Step to Activate ${premiumTierName}",
                              "font": { "size": 28, "weight": "semibold" },
                              "lineHeight": 1.05,
                              "color": { "appearance": "onBackground" },
                              "multilineAlignment": "center",
                              "style": {
                                "padding": { "top": 16, "leading": 24, "trailing": 24, "bottom": 24 },
                                "frame": { "maxWidth": "infinity" }
                              }
                            }
                          },
                          {
                            "vStack": {
                              "spacing": 10,
                              "alignment": "leading",
                              "children": [
                                { "text": { "text": "Enter your email", "font": { "size": 15, "weight": "semibold" }, "color": { "appearance": "onBackground" } } },
                                {
                                  "textField": {
                                    "valueKey": "email",
                                    "placeholder": "you@email.com",
                                    "keyboardType": "emailAddress",
                                    "textContentType": "emailAddress",
                                    "style": { "padding": { "top": 14, "leading": 16, "bottom": 14, "trailing": 16 }, "cornerRadius": 12, "backgroundColor": { "appearance": "surface" }, "frame": { "maxWidth": "infinity" } }
                                  }
                                },
                                {
                                  "conditional": {
                                    "condition": { "hasValue": "emailError" },
                                    "ifTrue": { "text": { "text": "", "valueKey": "emailError", "font": { "size": 13, "weight": "regular" }, "color": { "appearance": "error" } } }
                                  }
                                }
                              ],
                              "style": { "padding": { "leading": 24, "trailing": 24, "bottom": 20 } }
                            }
                          },
                          {
                            "vStack": {
                              "spacing": 10,
                              "alignment": "leading",
                              "children": [
                                { "text": { "text": "You'll get", "font": { "size": 14, "weight": "medium" }, "color": { "appearance": "muted" } } },
                                {
                                  "hStack": {
                                    "spacing": 8,
                                    "alignment": "center",
                                    "children": [
                                      { "systemImage": { "systemName": "checkmark.circle.fill", "font": { "size": 18, "weight": "regular" }, "color": { "appearance": "accent" } } },
                                      { "text": { "text": "${premiumTierName} sponsored by ${selectedAdvertiserName}", "font": { "size": 15, "weight": "medium" }, "color": { "appearance": "onBackground" } } }
                                    ]
                                  }
                                },
                                {
                                  "hStack": {
                                    "spacing": 8,
                                    "alignment": "center",
                                    "children": [
                                      { "systemImage": { "systemName": "checkmark.circle.fill", "font": { "size": 18, "weight": "regular" }, "color": { "appearance": "accent" } } },
                                      { "text": { "text": "Best of internet, limited time ${selectedAdvertiserName} deal", "font": { "size": 15, "weight": "medium" }, "color": { "appearance": "onBackground" } } }
                                    ]
                                  }
                                },
                                {
                                  "hStack": {
                                    "spacing": 8,
                                    "alignment": "center",
                                    "children": [
                                      { "systemImage": { "systemName": "checkmark.circle.fill", "font": { "size": 18, "weight": "regular" }, "color": { "appearance": "accent" } } },
                                      { "text": { "text": "Trial end reminders for ${appName} in your inbox", "font": { "size": 15, "weight": "medium" }, "color": { "appearance": "onBackground" } } }
                                    ]
                                  }
                                }
                              ],
                              "style": { "padding": { "leading": 24, "trailing": 24 }, "frame": { "maxWidth": "infinity", "alignment": "leading" } }
                            }
                          },
                          { "spacer": {} },
                          {
                            "vStack": {
                              "spacing": 10,
                              "alignment": "center",
                              "children": [
                                {
                                  "button": {
                                    "content": { "text": { "text": "Activate Gifted Trial", "font": { "size": 17, "weight": "bold" }, "color": { "appearance": "onAccent" } } },
                                    "action": { "type": "submitLead", "onSuccessState": "iap" },
                                    "style": { "frame": { "maxWidth": "infinity" }, "padding": { "top": 16, "bottom": 16 }, "cornerRadius": 28, "backgroundColor": { "appearance": "accent" }, "shadow": { "color": { "appearance": "accent" }, "radius": 12, "x": 0, "y": 4, "opacity": 0.4 } }
                                  }
                                },
                                {
                                  "hStack": {
                                    "spacing": 6,
                                    "alignment": "center",
                                    "children": [
                                      { "systemImage": { "systemName": "gift.fill", "font": { "size": 13, "weight": "medium" }, "color": { "appearance": "accent" } } },
                                      { "text": { "text": "Subscription sponsored by ${selectedAdvertiserName}", "font": { "size": 13, "weight": "medium" }, "color": { "appearance": "muted" } } }
                                    ]
                                  }
                                }
                              ],
                              "style": { "padding": { "top": 12, "leading": 24, "trailing": 24, "bottom": 48 } }
                            }
                          }
                        ],
                        "style": { "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" }, "ignoresSafeArea": true }
                      }
                    }
                  ]
                }
              },
              "ifFalse": {
                "conditional": {
                  "condition": { "stateEquals": "iap" },
                  "ifTrue": {
                    "zStack": {
                      "alignment": "center",
                      "children": [
                        { "shape": { "type": "rectangle", "fillColor": { "appearance": "background" }, "style": { "ignoresSafeArea": true } } },
                        {
                          "vStack": {
                            "spacing": 16,
                            "alignment": "center",
                            "children": [
                              { "systemImage": { "systemName": "lock.open.fill", "font": { "size": 44, "weight": "semibold" }, "color": { "appearance": "accent" } } },
                              { "text": { "text": "Unlocking ${appName}...", "font": { "size": 20, "weight": "semibold" }, "color": { "appearance": "onBackground" }, "multilineAlignment": "center" } },
                              { "text": { "text": "Complete your subscription in the App Store sheet.", "font": { "size": 14, "weight": "regular" }, "color": { "appearance": "muted" }, "multilineAlignment": "center" } }
                            ],
                            "style": { "padding": { "all": 32 }, "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "center" } }
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
"""
}
#endif
