//
//  SDUIVariant_LeadCapture.swift
//  Encore
//
//  Lead capture flow: offers → email capture → IAP.
//  Zero-redirect CPL model — email is captured natively, then StoreKit IAP fires.
//
//  Usage: Add `-SDUIDevVariant leadCapture` to Xcode scheme launch arguments.
//

#if DEBUG
enum SDUIVariant_LeadCapture {
    static let json = """
{
    "version": "2.0.0",
    "initialState": "offers",
    "presentationDetents": [0.54, 0.95],
    "cornerRadius": null,
    "showDragIndicator": false,
    "stateDetents": {
        "offers": [0.54, 0.95],
        "capture": [0.54],
        "iap": [0.3]
    },
    "stateActions": {
        "iap": {
            "onEnter": {
                "type": "triggerIAP",
                "onSuccessState": "thankYou",
                "onCancelAction": "capture"
            }
        }
    },
    "root": {
        "conditional": {
            "condition": { "stateEquals": "offers" },
            "ifTrue": {
                "zStack": {
                    "alignment": "top",
                    "children": [
                        {
                            "shape": {
                                "type": "rectangle",
                                "fillColor": { "semantic": "systemGroupedBackground" },
                                "style": { "ignoresSafeArea": true }
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
                                                        "fillColor": { "semantic": "separator" },
                                                        "style": {
                                                            "padding": { "top": 8 },
                                                            "frame": { "width": 46, "height": 5 }
                                                        }
                                                    }
                                                },
                                                {
                                                    "hStack": {
                                                        "children": [
                                                            { "spacer": {} },
                                                            {
                                                                "button": {
                                                                    "content": {
                                                                        "systemImage": {
                                                                            "systemName": "xmark",
                                                                            "font": { "size": 15, "weight": "semibold" },
                                                                            "color": { "semantic": "tertiaryLabel" }
                                                                        }
                                                                    },
                                                                    "action": "close",
                                                                    "style": { "padding": { "top": 20, "trailing": 20 } }
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
                                                                    "font": { "size": 24, "weight": "semibold" },
                                                                    "segments": [
                                                                        { "text": "Get ${appName}", "color": { "semantic": "label" } },
                                                                        { "text": " for free", "color": { "hex": "#6743F5" } }
                                                                    ]
                                                                }
                                                            },
                                                            {
                                                                "text": {
                                                                    "text": "Claim your brand sponsor for ${trialValue} ${trialUnit} free",
                                                                    "font": { "size": 17, "weight": "regular" },
                                                                    "color": { "semantic": "secondaryLabel" }
                                                                }
                                                            }
                                                        ],
                                                        "style": {
                                                            "padding": { "top": 2, "leading": 20, "trailing": 40 },
                                                            "frame": { "maxWidth": "infinity", "alignment": "leading" }
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
                                            "contentMargins": { "horizontal": 20 },
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
                                                                                    "placeholderColor": { "semantic": "tertiarySystemFill" },
                                                                                    "style": {
                                                                                        "frame": { "maxWidth": "infinity" },
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
                                                                                                "placeholderColor": { "semantic": "tertiarySystemFill" },
                                                                                                "style": {
                                                                                                    "frame": { "width": 42, "height": 42 },
                                                                                                    "cornerRadius": 8,
                                                                                                    "clipShape": { "rectangle": { "cornerRadius": 8 } }
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
                                                                                                            "font": { "size": 16, "weight": "semibold" },
                                                                                                            "color": { "semantic": "label" },
                                                                                                            "lineLimit": 1
                                                                                                        }
                                                                                                    },
                                                                                                    {
                                                                                                        "text": {
                                                                                                            "text": "",
                                                                                                            "textBinding": "offerDescription",
                                                                                                            "font": { "size": 14, "weight": "regular" },
                                                                                                            "color": { "semantic": "secondaryLabel" },
                                                                                                            "lineLimit": 1,
                                                                                                            "multilineAlignment": "leading"
                                                                                                        }
                                                                                                    }
                                                                                                ]
                                                                                            }
                                                                                        },
                                                                                        { "spacer": { "minLength": 8 } },
                                                                                        {
                                                                                            "button": {
                                                                                                "content": {
                                                                                                    "text": {
                                                                                                        "text": "Claim",
                                                                                                        "textBinding": "offerCtaText",
                                                                                                        "font": { "size": 16, "weight": "semibold" },
                                                                                                        "color": { "hex": "#FFFFFF" },
                                                                                                        "lineHeight": 1.2
                                                                                                    }
                                                                                                },
                                                                                                "action": { "type": "setState", "setState": "capture" },
                                                                                                "style": {
                                                                                                    "padding": { "top": 12, "leading": 24, "bottom": 12, "trailing": 24 },
                                                                                                    "frame": { "minWidth": 100 },
                                                                                                    "cornerRadius": 9999,
                                                                                                    "backgroundColor": { "hex": "#6743F5" },
                                                                                                    "shadow": { "color": { "hex": "#6743F5" }, "radius": 8, "x": 0, "y": 4 }
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    ],
                                                                                    "style": {
                                                                                        "padding": { "top": 14, "leading": 16, "bottom": 14, "trailing": 16 },
                                                                                        "backgroundColor": { "semantic": "secondarySystemGroupedBackground" }
                                                                                    }
                                                                                }
                                                                            }
                                                                        ],
                                                                        "style": {
                                                                            "containerRelativeFrame": { "axis": "horizontal" },
                                                                            "cornerRadius": 16,
                                                                            "backgroundColor": { "semantic": "secondarySystemGroupedBackground" },
                                                                            "shadow": { "color": { "semantic": "label" }, "radius": 4, "x": 0, "y": 0 }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    ],
                                                    "style": { "scrollTargetLayout": true }
                                                }
                                            },
                                            "style": { "padding": { "top": 20 } }
                                        }
                                    },
                                    {
                                        "conditional": {
                                            "condition": { "hasMultipleOffers": {} },
                                            "ifTrue": {
                                                "group": {
                                                    "content": { "compactPageIndicator": {} },
                                                    "style": { "padding": { "top": 15 } }
                                                }
                                            }
                                        }
                                    },
                                    { "spacer": {} }
                                ],
                                "style": {
                                    "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "top" },
                                    "ignoresSafeArea": true
                                }
                            }
                        },
                        { "empty": {} }
                    ]
                }
            },
            "ifFalse": {
                "conditional": {
                    "condition": { "stateEquals": "capture" },
                    "ifTrue": {
                        "vStack": {
                            "spacing": 0,
                            "children": [
                                {
                                    "shape": {
                                        "type": "roundedRectangle",
                                        "cornerRadius": 2.5,
                                        "fillColor": { "semantic": "separator" },
                                        "style": {
                                            "padding": { "top": 8 },
                                            "frame": { "width": 46, "height": 5 }
                                        }
                                    }
                                },
                                {
                                    "hStack": {
                                        "children": [
                                            {
                                                "button": {
                                                    "content": {
                                                        "systemImage": {
                                                            "systemName": "chevron.left",
                                                            "font": { "size": 15, "weight": "semibold" },
                                                            "color": { "semantic": "tertiaryLabel" }
                                                        }
                                                    },
                                                    "action": { "type": "setState", "setState": "offers" },
                                                    "style": { "padding": { "top": 20, "leading": 20 } }
                                                }
                                            },
                                            { "spacer": {} },
                                            {
                                                "button": {
                                                    "content": {
                                                        "systemImage": {
                                                            "systemName": "xmark",
                                                            "font": { "size": 15, "weight": "semibold" },
                                                            "color": { "semantic": "tertiaryLabel" }
                                                        }
                                                    },
                                                    "action": "close",
                                                    "style": { "padding": { "top": 20, "trailing": 20 } }
                                                }
                                            }
                                        ]
                                    }
                                },
                                {
                                    "vStack": {
                                        "spacing": 16,
                                        "alignment": "leading",
                                        "children": [
                                            {
                                                "text": {
                                                    "text": "",
                                                    "font": { "size": 22, "weight": "bold" },
                                                    "segments": [
                                                        { "text": "Congrats! ", "color": { "semantic": "label" } },
                                                        { "text": "", "textBinding": "offerAdvertiserName", "color": { "hex": "#6743F5" } },
                                                        { "text": " is sponsoring your subscription \u{2728}", "color": { "semantic": "label" } }
                                                    ]
                                                }
                                            },
                                            {
                                                "text": {
                                                    "text": "Enter your email to activate your sponsorship.",
                                                    "font": { "size": 15, "weight": "regular" },
                                                    "color": { "semantic": "secondaryLabel" }
                                                }
                                            },
                                            {
                                                "textField": {
                                                    "valueKey": "email",
                                                    "placeholder": "you@example.com",
                                                    "keyboardType": "emailAddress",
                                                    "textContentType": "emailAddress",
                                                    "style": {
                                                        "padding": { "top": 14, "leading": 16, "bottom": 14, "trailing": 16 },
                                                        "cornerRadius": 12,
                                                        "backgroundColor": { "semantic": "secondarySystemGroupedBackground" }
                                                    }
                                                }
                                            },
                                            {
                                                "conditional": {
                                                    "condition": { "hasValue": "emailError" },
                                                    "ifTrue": {
                                                        "text": {
                                                            "text": "",
                                                            "valueKey": "emailError",
                                                            "font": { "size": 13, "weight": "regular" },
                                                            "color": { "hex": "#FF3B30" }
                                                        }
                                                    }
                                                }
                                            },
                                            {
                                                "toggle": {
                                                    "valueKey": "remindToCancel",
                                                    "label": {
                                                        "text": {
                                                            "text": "Remind me 2 days before trial renews",
                                                            "font": { "size": 15, "weight": "medium" },
                                                            "color": { "semantic": "label" }
                                                        }
                                                    }
                                                }
                                            },
                                            { "spacer": {} },
                                            {
                                                "slideButton": {
                                                    "text": "Slide to Unlock",
                                                    "disabledText": "Enter Email",
                                                    "action": { "type": "submitLead", "onSuccessState": "iap" },
                                                    "trackColor": { "semantic": "tertiarySystemFill" },
                                                    "thumbColor": { "hex": "#6743F5" },
                                                    "textColor": { "semantic": "secondaryLabel" },
                                                    "requiredValueKey": "email"
                                                }
                                            }
                                        ],
                                        "style": {
                                            "padding": { "top": 8, "leading": 24, "trailing": 24, "bottom": 24 },
                                            "frame": { "maxWidth": "infinity", "maxHeight": "infinity", "alignment": "topLeading" }
                                        }
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
"""
}
#endif
