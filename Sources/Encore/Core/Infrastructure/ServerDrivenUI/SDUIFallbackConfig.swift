//
//  SDUIFallbackConfig.swift
//  Encore
//
//  Fallback JSON configuration for server-driven UI
//  This is the source of truth for the offer sheet layout
//

import Foundation

/// Contains fallback SDUI configurations
/// In the future, these can be fetched from a server instead
enum SDUIFallbackConfig {
    
    /// Parses the presentation style from the embedded JSON config
    static var presentationStyle: SDUIPresentationStyle {
        guard let data = offerSheetJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let styleString = json["presentationStyle"] as? String,
              let style = SDUIPresentationStyle(rawValue: styleString) else {
            return .default
        }
        return style
    }
    
    /// The offer sheet JSON configuration
    /// Source: offer-sheet-config.json
    static let offerSheetJSON = """
{
    "version": "1.0.0",
    "presentationDetents": [
        0.54,
        0.95
    ],
    "cornerRadius": null,
    "showDragIndicator": false,
    "root": {
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
                                                                    "text": "Get ${trialValue} ${trialUnit} of ${appName}",
                                                                    "color": {
                                                                        "semantic": "label"
                                                                    }
                                                                },
                                                                {
                                                                    "text": " for free",
                                                                    "color": {
                                                                        "hex": "#16BD25"
                                                                    }
                                                                }
                                                            ],
                                                            "style": {
                                                                "padding": {
                                                                    "trailing": 90
                                                                }
                                                            }
                                                        }
                                                    },
                                                    {
                                                        "text": {
                                                            "text": "Claim an exclusive deal and get ${appName} for free",
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
                                        }
                                    ]
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
                                                                                            "cornerRadius": 8,
                                                                                            "clipShape": {
                                                                                                "rectangle": {
                                                                                                    "cornerRadius": 8
                                                                                                }
                                                                                            }
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
                                                                                                    "lineLimit": 1,
                                                                                                    "multilineAlignment": "leading"
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
                                                                                    "button": {
                                                                                        "content": {
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
                                                                                                "lineHeight": 1.2
                                                                                            }
                                                                                        },
                                                                                        "action": "claimOffer",
                                                                                        "style": {
                                                                                            "padding": {
                                                                                                "top": 8.5,
                                                                                                "leading": 19.5,
                                                                                                "bottom": 8.5,
                                                                                                "trailing": 19.5
                                                                                            },
                                                                                            "frame": {
                                                                                                "minWidth": 78
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
                                                                ],
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
                                "conditional": {
                                    "condition": {
                                        "hasMultipleOffers": {}
                                    },
                                    "ifTrue": {
                                        "group": {
                                            "content": {
                                                "compactPageIndicator": {}
                                            },
                                            "style": {
                                                "padding": {
                                                    "top": 15
                                                }
                                            }
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
"""
}
