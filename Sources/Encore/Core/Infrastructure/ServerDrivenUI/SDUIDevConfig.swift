//
//  SDUIDevConfig.swift
//  Encore
//
//  Local JSON configuration for SDUI development.
//  Only included in DEBUG builds for testing.
//

import Foundation

/// Local development configuration for Server-Driven UI
enum SDUIDevConfig {
    
    #if DEBUG
    // MARK: - Dev Config Toggle
    
    /// Set to true to use the local dev JSON instead of remote config
    static let useDevConfig = false
    
    /// Mock variant ID for analytics when using dev config
    static let mockVariantId: String? = "83abb4d7-c185-4ba6-95b9-75e735e00a14"
    
    // MARK: - Dev JSON Config
    
    /// IAP-First Flow Dev Config
    ///
    /// This config demonstrates the IAP-first flow:
    /// 1. IAP is triggered immediately BEFORE showing any UI (via triggerIAPFirst)
    /// 2. On IAP success, the offer sheet appears with "subscribed" state (thank you + offers)
    /// 3. On IAP cancel, nothing is shown (user stays in app)
    ///
    /// Config:
    /// - triggerIAPFirst: true
    /// - initialState: "subscribed" (shown after IAP success)
    static let devJSON = """
{
    "version": "1.0.0",
    "presentationStyle": "sheet",
    "presentationDetents": [
        1.0
    ],
    "showDragIndicator": false,
    "initialState": "paywall",
    "stateDetents": {
        "paywall": [
            1.0
        ],
        "thankYou": [
            0.44,
            0.95
        ]
    },
    "root": {
        "conditional": {
            "condition": {
                "stateEquals": "paywall"
            },
            "ifTrue": {
                "zStack": {
                    "children": [
                        {
                            "shape": {
                                "type": "rectangle",
                                "fillColor": {
                                    "hex": "#1a1a2e"
                                }
                            }
                        },
                        {
                            "vStack": {
                                "spacing": 0,
                                "children": [
                                    {
                                        "spacer": {}
                                    },
                                    {
                                        "systemImage": {
                                            "systemName": "sparkles",
                                            "font": {
                                                "size": 52,
                                                "weight": "regular"
                                            },
                                            "color": {
                                                "hex": "#FFD700"
                                            }
                                        }
                                    },
                                    {
                                        "text": {
                                            "text": "${appName} Premium",
                                            "font": {
                                                "size": 32,
                                                "weight": "bold"
                                            },
                                            "color": {
                                                "hex": "#FFFFFF"
                                            },
                                            "style": {
                                                "padding": {
                                                    "top": 16
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "text": {
                                            "text": "Track your nutrition effortlessly with AI-powered meal logging, personalized insights, and detailed analytics.",
                                            "font": {
                                                "size": 16,
                                                "weight": "regular"
                                            },
                                            "color": {
                                                "hex": "#AAAAAA"
                                            },
                                            "multilineAlignment": "center",
                                            "style": {
                                                "padding": {
                                                    "top": 12,
                                                    "leading": 32,
                                                    "trailing": 32
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "vStack": {
                                            "spacing": 8,
                                            "alignment": "leading",
                                            "children": [
                                                {
                                                    "text": {
                                                        "text": "Plus exclusive partner offers:",
                                                        "font": {
                                                            "size": 14,
                                                            "weight": "semibold"
                                                        },
                                                        "color": {
                                                            "hex": "#16BD25"
                                                        }
                                                    }
                                                },
                                                {
                                                    "forEach": {
                                                        "dataSource": "offers",
                                                        "itemTemplate": {
                                                            "text": {
                                                                "text": "• ",
                                                                "textBinding": "offerAdvertiserName",
                                                                "font": {
                                                                    "size": 15,
                                                                    "weight": "medium"
                                                                },
                                                                "color": {
                                                                    "hex": "#FFFFFF"
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            ],
                                            "style": {
                                                "padding": {
                                                    "top": 24
                                                },
                                                "frame": {
                                                    "maxWidth": "infinity",
                                                    "alignment": "leading"
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "spacer": {}
                                    },
                                    {
                                        "button": {
                                            "content": {
                                                "text": {
                                                    "text": "Subscribe - ${subscriptionPrice}${subscriptionPeriod}",
                                                    "font": {
                                                        "size": 18,
                                                        "weight": "bold"
                                                    },
                                                    "color": {
                                                        "hex": "#FFFFFF"
                                                    }
                                                }
                                            },
                                            "action": {
                                                "type": "triggerIAP",
                                                "onSuccessState": "thankYou"
                                            },
                                            "style": {
                                                "frame": {
                                                    "maxWidth": "infinity"
                                                },
                                                "padding": {
                                                    "top": 18,
                                                    "bottom": 18
                                                },
                                                "cornerRadius": 14,
                                                "backgroundColor": {
                                                    "hex": "#6743F5"
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "button": {
                                            "content": {
                                                "text": {
                                                    "text": "Not now",
                                                    "font": {
                                                        "size": 16,
                                                        "weight": "medium"
                                                    },
                                                    "color": {
                                                        "hex": "#888888"
                                                    }
                                                }
                                            },
                                            "action": "close",
                                            "style": {
                                                "padding": {
                                                    "top": 16
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "text": {
                                            "text": "Cancel anytime. Terms & Privacy Policy apply.",
                                            "font": {
                                                "size": 12,
                                                "weight": "regular"
                                            },
                                            "color": {
                                                "hex": "#666666"
                                            },
                                            "style": {
                                                "padding": {
                                                    "top": 12,
                                                    "bottom": 40
                                                }
                                            }
                                        }
                                    }
                                ],
                                "style": {
                                    "padding": {
                                        "leading": 24,
                                        "trailing": 24
                                    },
                                    "frame": {
                                        "maxWidth": "infinity",
                                        "maxHeight": "infinity"
                                    }
                                }
                            }
                        }
                    ]
                }
            },
            "ifFalse": {
                "zStack": {
                    "alignment": "top",
                    "children": [
                        {
                            "shape": {
                                "type": "rectangle",
                                "fillColor": {
                                    "semantic": "systemGroupedBackground"
                                },
                                "style": {
                                    "ignoresSafeArea": true
                                }
                            }
                        },
                        {
                            "vStack": {
                                "spacing": 0,
                                "children": [
                                    {
                                        "shape": {
                                            "type": "roundedRectangle",
                                            "cornerRadius": 2.5,
                                            "fillColor": {
                                                "semantic": "separator"
                                            },
                                            "style": {
                                                "padding": {
                                                    "top": 8
                                                },
                                                "frame": {
                                                    "width": 46,
                                                    "height": 5
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "hStack": {
                                            "children": [
                                                {
                                                    "spacer": {}
                                                },
                                                {
                                                    "button": {
                                                        "content": {
                                                            "systemImage": {
                                                                "systemName": "xmark",
                                                                "font": {
                                                                    "size": 15,
                                                                    "weight": "semibold"
                                                                },
                                                                "color": {
                                                                    "semantic": "tertiaryLabel"
                                                                }
                                                            }
                                                        },
                                                        "action": "close",
                                                        "style": {
                                                            "padding": {
                                                                "top": 20,
                                                                "trailing": 20
                                                            }
                                                        }
                                                    }
                                                }
                                            ]
                                        }
                                    },
                                    {
                                        "vStack": {
                                            "spacing": 8,
                                            "alignment": "leading",
                                            "children": [
                                                {
                                                    "text": {
                                                        "text": "",
                                                        "font": {
                                                            "size": 24,
                                                            "weight": "semibold"
                                                        },
                                                        "segments": [
                                                            {
                                                                "text": "Thank you",
                                                                "color": {
                                                                    "hex": "#16BD25"
                                                                }
                                                            },
                                                            {
                                                                "text": " for subscribing!",
                                                                "color": {
                                                                    "semantic": "label"
                                                                }
                                                            }
                                                        ]
                                                    }
                                                },
                                                {
                                                    "text": {
                                                        "text": "Claim your exclusive partner offers below",
                                                        "font": {
                                                            "size": 17,
                                                            "weight": "regular"
                                                        },
                                                        "color": {
                                                            "semantic": "secondaryLabel"
                                                        },
                                                        "lineSpacing": 2
                                                    }
                                                }
                                            ],
                                            "style": {
                                                "padding": {
                                                    "top": 2,
                                                    "leading": 20,
                                                    "trailing": 40
                                                },
                                                "frame": {
                                                    "maxWidth": "infinity",
                                                    "alignment": "leading"
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "scrollView": {
                                            "axis": "horizontal",
                                            "showsIndicators": false,
                                            "scrollTargetBehavior": "viewAligned",
                                            "contentMargins": {
                                                "horizontal": 20
                                            },
                                            "content": {
                                                "hStack": {
                                                    "spacing": 12,
                                                    "children": [
                                                        {
                                                            "forEach": {
                                                                "dataSource": "offers",
                                                                "itemTemplate": {
                                                                    "button": {
                                                                        "content": {
                                                                            "vStack": {
                                                                                "spacing": 0,
                                                                                "children": [
                                                                                    {
                                                                                        "asyncImage": {
                                                                                            "urlBinding": "offerPrimaryCreative",
                                                                                            "contentMode": "fit",
                                                                                            "aspectRatio": 2.369,
                                                                                            "placeholderColor": {
                                                                                                "semantic": "tertiarySystemFill"
                                                                                            },
                                                                                            "style": {
                                                                                                "frame": {
                                                                                                    "maxWidth": "infinity"
                                                                                                },
                                                                                                "clipped": true,
                                                                                                "cornerRadius": 16
                                                                                            }
                                                                                        }
                                                                                    },
                                                                                    {
                                                                                        "hStack": {
                                                                                            "spacing": 12,
                                                                                            "alignment": "center",
                                                                                            "children": [
                                                                                                {
                                                                                                    "asyncImage": {
                                                                                                        "urlBinding": "offerLogoImage",
                                                                                                        "contentMode": "fit",
                                                                                                        "placeholderColor": {
                                                                                                            "semantic": "tertiarySystemFill"
                                                                                                        },
                                                                                                        "style": {
                                                                                                            "frame": {
                                                                                                                "width": 42,
                                                                                                                "height": 42
                                                                                                            },
                                                                                                            "cornerRadius": 8
                                                                                                        }
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
                                                                                                                    "font": {
                                                                                                                        "size": 16,
                                                                                                                        "weight": "semibold"
                                                                                                                    },
                                                                                                                    "color": {
                                                                                                                        "semantic": "label"
                                                                                                                    },
                                                                                                                    "lineLimit": 1
                                                                                                                }
                                                                                                            },
                                                                                                            {
                                                                                                                "text": {
                                                                                                                    "text": "",
                                                                                                                    "textBinding": "offerDescription",
                                                                                                                    "font": {
                                                                                                                        "size": 14,
                                                                                                                        "weight": "regular"
                                                                                                                    },
                                                                                                                    "color": {
                                                                                                                        "semantic": "secondaryLabel"
                                                                                                                    },
                                                                                                                    "lineLimit": 1
                                                                                                                }
                                                                                                            }
                                                                                                        ]
                                                                                                    }
                                                                                                },
                                                                                                {
                                                                                                    "spacer": {
                                                                                                        "minLength": 8
                                                                                                    }
                                                                                                },
                                                                                                {
                                                                                                    "text": {
                                                                                                        "text": "Claim",
                                                                                                        "textBinding": "offerCtaText",
                                                                                                        "font": {
                                                                                                            "size": 14,
                                                                                                            "weight": "semibold"
                                                                                                        },
                                                                                                        "color": {
                                                                                                            "hex": "#FFFFFF"
                                                                                                        },
                                                                                                        "style": {
                                                                                                            "padding": {
                                                                                                                "top": 8.5,
                                                                                                                "leading": 19.5,
                                                                                                                "bottom": 8.5,
                                                                                                                "trailing": 19.5
                                                                                                            },
                                                                                                            "cornerRadius": 9999,
                                                                                                            "backgroundColor": {
                                                                                                                "hex": "#6743F5"
                                                                                                            }
                                                                                                        }
                                                                                                    }
                                                                                                }
                                                                                            ],
                                                                                            "style": {
                                                                                                "padding": {
                                                                                                    "top": 14,
                                                                                                    "leading": 16,
                                                                                                    "bottom": 14,
                                                                                                    "trailing": 16
                                                                                                },
                                                                                                "backgroundColor": {
                                                                                                    "semantic": "secondarySystemGroupedBackground"
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                ]
                                                                            }
                                                                        },
                                                                        "action": "claimOffer",
                                                                        "style": {
                                                                            "containerRelativeFrame": {
                                                                                "axis": "horizontal"
                                                                            },
                                                                            "cornerRadius": 16,
                                                                            "backgroundColor": {
                                                                                "semantic": "secondarySystemGroupedBackground"
                                                                            },
                                                                            "shadow": {
                                                                                "color": {
                                                                                    "semantic": "label"
                                                                                },
                                                                                "radius": 4,
                                                                                "x": 0,
                                                                                "y": 0
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    ],
                                                    "style": {
                                                        "scrollTargetLayout": true
                                                    }
                                                }
                                            },
                                            "style": {
                                                "padding": {
                                                    "top": 20
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "spacer": {}
                                    },
                                    {
                                        "conditional": {
                                            "condition": {
                                                "hasMultipleOffers": {}
                                            },
                                            "ifTrue": {
                                                "hStack": {
                                                    "spacing": 0,
                                                    "children": [
                                                        {
                                                            "forEach": {
                                                                "dataSource": "pageIndicators",
                                                                "itemTemplate": {
                                                                    "conditional": {
                                                                        "condition": {
                                                                            "isCurrentPageBinding": {}
                                                                        },
                                                                        "ifTrue": {
                                                                            "group": {
                                                                                "content": {
                                                                                    "shape": {
                                                                                        "type": "capsule",
                                                                                        "fillColor": {
                                                                                            "hex": "#5671FF"
                                                                                        },
                                                                                        "style": {
                                                                                            "frame": {
                                                                                                "width": 18,
                                                                                                "height": 8
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                },
                                                                                "style": {
                                                                                    "padding": {
                                                                                        "horizontal": 1
                                                                                    }
                                                                                }
                                                                            }
                                                                        },
                                                                        "ifFalse": {
                                                                            "group": {
                                                                                "content": {
                                                                                    "shape": {
                                                                                        "type": "circle",
                                                                                        "fillColor": {
                                                                                            "semantic": "tertiaryLabel"
                                                                                        },
                                                                                        "style": {
                                                                                            "frame": {
                                                                                                "width": 8,
                                                                                                "height": 8
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                },
                                                                                "style": {
                                                                                    "padding": {
                                                                                        "horizontal": 4
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    ]
                                                }
                                            }
                                        }
                                    },
                                    {
                                        "spacer": {}
                                    }
                                ],
                                "style": {
                                    "frame": {
                                        "maxWidth": "infinity",
                                        "maxHeight": "infinity",
                                        "alignment": "top"
                                    },
                                    "ignoresSafeArea": true
                                }
                            }
                            
                        },
                        {
                            "empty": {}
                        }
                    ]
                }
            }
        }
    }
}
"""
    #else
    // Empty stub for release builds - devJSON is only needed in DEBUG
    static let useDevConfig = false
    static let mockVariantId: String? = nil
   static let devJSON = "{}"
    #endif
}
